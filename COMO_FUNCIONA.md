# Cómo funciona este proyecto

Este proyecto simula el sistema de notificaciones de emergencia de AlertMedia.
Un cliente dispara una alerta → el sistema la envía a miles de personas via SMS, Email y Push.

---

## El problema que resuelve

Cuando llega una alerta para 500 personas, no puedes:
- Procesarla de forma síncrona (el cliente esperaría minutos)
- Enviar una notificación a la vez (demasiado lento)
- Ignorar los fallos (es una emergencia, necesitas reintentos)

La solución usa tres herramientas de OTP trabajando juntas: Broadway, DynamicSupervisor y GenServer.

---

## Qué hace cada módulo

### `alert_media.ex` — El punto de entrada (simula el Controller HTTP)

Representa el `POST /alerts` que haría un cliente.
Hace exactamente tres cosas y responde inmediatamente:

1. Mete los mensajes en la cola (fan-out — uno por persona por canal)
2. Levanta un AlertWorker para rastrear el estado de esta alerta
3. Retorna `{:ok, alert_id}` — no espera a que se entregue nada

```
AlertMedia.trigger_alert(%{id: "alert-1", recipients: ["juan", "maria"]})
```

---

### `application.ex` — El árbol de supervisión (arranca al iniciar el servidor)

Define qué procesos deben estar vivos desde el inicio.
No hace trabajo — solo levanta y supervisa a los demás.

```
Supervisor principal
  ├── Registry          — directorio de AlertWorkers vivos (buscar por alert_id)
  ├── DynamicSupervisor — padre de los AlertWorkers, vacío hasta que llegue una alerta
  └── BroadwayPipeline  — siempre escuchando la cola, desde el primer segundo
```

**¿Por qué BroadwayPipeline aquí y no en DynamicSupervisor?**
Porque Broadway debe estar vivo todo el tiempo, no solo cuando llega una alerta.
DynamicSupervisor es para procesos que nacen y mueren con cada alerta.

---

### `alert_producer.ex` — La cola de mensajes (simula SQS)

En producción esto sería `BroadwaySQS.Producer` apuntando a AWS.
Aquí es una cola en memoria que acepta mensajes via `push/1` y los entrega a Broadway.

**Quién le manda mensajes:**
- `alert_media.ex` al recibir una alerta (fan-out inicial)
- `alert_worker.ex` cuando necesita reintentar un mensaje fallido

**Quién lee de él:**
- Broadway — le pregunta constantemente "¿tienes mensajes?"

---

### `broadway_pipeline.ex` — El procesador de mensajes (el trabajador de volumen)

Broadway mantiene N workers corriendo en paralelo.
Recibe mensajes de la cola y los procesa concurrentemente.

Tiene dos funciones que tú escribes:

**`handle_message/3`** — se llama UNA VEZ por mensaje individual
Solo decide a qué batcher va. No hace ningún trabajo real.
```
mensaje {juan, sms} → batcher :sms
mensaje {juan, email} → batcher :email
```

**`handle_batch/4`** — se llama cuando el batcher acumula 5 mensajes o pasa 1 segundo
Aquí sí se hace el trabajo: llama a Twilio/SES/FCM y notifica al AlertWorker del resultado.

**¿Qué NO hace Broadway?**
No recuerda nada. No sabe si Juan ya fue notificado antes.
No maneja reintentos complejos con backoff.
Solo procesa y olvida — para eso está el AlertWorker.

---

### `alert_worker.ex` — El rastreador de estado por alerta (un GenServer)

**Un AlertWorker = una alerta activa.**
Si llegan 3 alertas al mismo tiempo, hay 3 AlertWorkers corriendo en paralelo.

Es un GenServer (proceso largo) que vive desde que se crea la alerta hasta que
todos los destinatarios fueron procesados (entregados o con máximo reintentos).

**Qué guarda en memoria (su estado):**
```elixir
%{
  alert: %{id: "alert-1", recipients: ["juan", "maria"]},
  pending: [{"juan", "sms"}, {"juan", "email"}, {"maria", "push"}, ...],
  attempts: %{{"juan", "sms"} => 2}  # cuántos reintentos lleva cada uno
}
```

**Qué hace con cada mensaje que recibe:**

- `{:delivery_result, recipient, channel, :ok}` — lo tacha de pending, guarda en ETS
- `{:delivery_result, recipient, channel, :failed}` — programa un reintento en 5 segundos
- `{:retry, recipient, channel}` — vuelve a meter el mensaje en la cola
- Si `pending` queda vacío → el proceso muere limpiamente

**Crash recovery:**
Si el proceso crashea, el DynamicSupervisor lo reinicia.
En `init`, lo primero que hace es leer ETS (la "DB") para saber qué ya fue entregado.
Así continúa desde donde se quedó sin re-enviar nada.

**¿Cómo le llegan los mensajes?**
Broadway llama `AlertWorker.notify_result(...)` que internamente hace `send(pid, ...)`.
`send` mete el mensaje en el mailbox del proceso.
GenServer lo rutea automáticamente al `handle_info` que hace pattern match con ese mensaje.

---

## Flujo completo de una alerta

```
1. POST /alerts {id: "alert-1", recipients: ["juan", "maria"]}
        │
        ▼
2. alert_media.ex
   ├── AlertProducer.push({juan, sms})
   ├── AlertProducer.push({juan, email})
   ├── AlertProducer.push({juan, push})
   ├── AlertProducer.push({maria, sms})
   ├── AlertProducer.push({maria, email})
   ├── AlertProducer.push({maria, push})
   ├── DynamicSupervisor.start_child(AlertWorker, alert)  ← nace el worker
   └── responde {:ok, "alert-1"}  ← inmediato, no espera nada

3. AlertWorker inicia
   └── init: pending = [{juan,sms},{juan,email},{juan,push},{maria,sms}...]

4. Broadway lee mensajes del producer en paralelo
   ├── handle_message: {juan, sms}   → batcher :sms
   ├── handle_message: {juan, email} → batcher :email
   ├── handle_message: {maria, sms}  → batcher :sms
   └── ...

5. Batcher :sms acumula 5 mensajes (o pasa 1s)
   └── handle_batch: llama Twilio con los 5
       ├── {juan, sms}  → :ok   → send(worker, {:delivery_result, juan, sms, :ok})
       ├── {maria, sms} → :failed → send(worker, {:delivery_result, maria, sms, :failed})
       └── ...

6. AlertWorker recibe resultados
   ├── {juan, sms, :ok}     → tacha de pending, guarda en ETS
   ├── {maria, sms, :failed} → programa reintento en 5s
   └── ...

7. Cuando pending == []
   └── AlertWorker muere limpiamente
```

---

## La diferencia clave entre Broadway y AlertWorker

| | Broadway | AlertWorker |
|---|---|---|
| Qué es | Pipeline de workers concurrentes | GenServer con estado |
| Cuántos hay | 1 (siempre vivo) | 1 por alerta activa |
| Vive hasta | Siempre | Que termine la alerta |
| Qué sabe | Solo el mensaje actual | Todo el estado de la alerta |
| Reintentos | Básicos (por mensaje) | Complejos (backoff, conteo, por destinatario) |
| Para qué | Volumen y velocidad | Coordinación y estado |
