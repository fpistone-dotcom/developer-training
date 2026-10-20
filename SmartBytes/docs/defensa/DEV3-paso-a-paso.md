# DEV #3 · Paso a paso para la defensa (Renewal Opportunity y Renewal Quote automáticas)

> **Para qué sirve este documento:** es la guía para **mostrar y explicar** el DEV #3 en el Code Review, en el orden en que se ejecuta. El detalle completo (diseño, bloques, 15 preguntas, evidencia en el org, Build Tracker) está en [`docs/code-review/DEV3.md`](../code-review/DEV3.md). Acá no se repite, se referencia. Los patrones que se repiten en todos los DEV están en [`00-patrones-base.md`](00-patrones-base.md).
>
> Los números de línea son del commit `c4d87a0` (07/10/2026). Si el código cambia, revisarlos.

---

## 1. Requirement en 2 líneas (palabras de vendedor)

- "Cuando activo un Contract quiero ver **ya** la Opportunity de renovación en mi forecast, con los productos y cantidades que el cliente tiene hoy (Amendments incluidos)."
- "Y cuando faltan 30 días para que venza, quiero que la Renewal Quote aparezca sola, que la Opportunity avance de etapa y que me llegue un email con el link para empezar a trabajarla."

Texto original y tabla de partes (A)…(G): [DEV3.md §1](../code-review/DEV3.md#1-qué-pide-el-requirement).

---

## 2. Flujo lógico (sin código)

1. Son **dos momentos distintos**: la **activación** del Contract (alguien guarda un registro) y los **30 días antes del fin** (pasa el tiempo, nadie guarda nada).
2. En ninguno de los dos creamos registros a mano: **prendemos los flags nativos de CPQ** y CPQ arma la Opportunity o la Quote con su propia lógica, igual que con sus botones.
3. **Activación → trigger** (`before update` de Contract): si el Status **pasó** a Activated, tildo `SBQQ__RenewalForecast__c` en memoria. En ese mismo save CPQ crea la Renewal Opportunity.
4. **30 días → job nocturno** (Scheduler a las 3:00 + Batch de a 1): busca Contracts activados que vencen entre hoy y hoy + 30 y todavía sin Renewal Quote, tilda `SBQQ__RenewalQuoted__c` → CPQ crea la Renewal Quote. Después paso la Opportunity de Prospecting a Proposal/Price Quote.
5. **Email → trigger de Quote** (`after insert`): cada Renewal Quote **pedida** (el Contract tiene `RenewalQuoted = true`) le manda un email a su Owner con el link. Ese filtro deja afuera la Quote temporal que CPQ crea y borra al activar (el bug de la Q-00090).
6. El flag `RenewalQuoted = true` también funciona como marca de "ya procesado": la noche siguiente ese Contract no vuelve a entrar.

---

## 3. Cronología demo → código

### Vista general

```
PARTE 1 (cuando el usuario guarda)                 PARTE 2 (cuando pasa el tiempo)
Usuario: Contract → Activated                      3:00 · RenewalQuoteScheduler
  └─ ContractTrigger (before update)                 └─ RenewalQuoteBatch (tandas de 1)
       └─ RenewalForecast = true (en memoria)             └─ RenewalQuoted = true (1 update)
            └─ CPQ: crea la Renewal Opportunity                └─ CPQ: crea la Renewal Quote
            └─ CPQ: Quote TEMPORAL (sin email:                      └─ QuoteTrigger (after insert)
               el filtro la descarta)                                    └─ email al Owner con el link
                                                          └─ Opportunity: Prospecting → Proposal/Price Quote
```

### Parte 1: activo el Contract → se crea la Renewal Opportunity

Todo pasa en **una sola transacción** (T1), salvo el cálculo de precios de CPQ, que es asíncrono.

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Abro el Contract **00000110**: Draft, *Renewal Forecast* destildado, *Renewal Opportunity* vacío, 3 Subscriptions (125, +100, −10). **Edit → Status = Activated → Save.** | Update del Contract → `ContractTrigger`. | [ContractTrigger.trigger:11-13](../../force-app/main/default/triggers/ContractTrigger.trigger#L11-L13) | Solo escucha `before update`. `isBefore && isUpdate` → `ContractTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap )`. | **T1** · **before update** |
| 2 | (no se ve) | → handler | [ContractTriggerHandler.cls:35-37](../../force-app/main/default/classes/ContractTriggerHandler.cls#L35-L37) | Entrada `public static` → llama a `setRenewalForecastOnActivation` (`private static`). | T1 · before update |
| 3 | (no se ve) | → detectar el cambio | [ContractTriggerHandler.cls:53-55](../../force-app/main/default/classes/ContractTriggerHandler.cls#L53-L55) | `oldContractByIdMap.get( newContract.Id )` y `statusChanged = new != old`: Draft → Activated **cambió**. | T1 · before update |
| 4 | (no se ve) | → tildar el flag | [ContractTriggerHandler.cls:56-58](../../force-app/main/default/classes/ContractTriggerHandler.cls#L56-L58) | Si cambió **a** `STATUS_ACTIVATED` ([:24](../../force-app/main/default/classes/ContractTriggerHandler.cls#L24)) y el flag está en false → `SBQQ__RenewalForecast__c = true` **en memoria**. **0 SOQL, 0 DML.** | T1 · before update |
| 5 | (no se ve) | Salesforce guarda el Contract con el flag → corre **`SBQQ.ContractAfter`** (trigger de CPQ). | — (código de CPQ) | CPQ ve el flag en true → crea la **Renewal Opportunity** (Prospecting, cierre = fin del Contract, `SBQQ__RenewedContract__c` = el Contract, **1 línea de 215** = 125 + 100 − 10) y completa `SBQQ__RenewalOpportunity__c` en el Contract. | T1 · after update (de CPQ) |
| 6 | (no se ve) | Ese update de CPQ sobre el Contract vuelve a disparar `ContractTrigger`. | [ContractTriggerHandler.cls:55](../../force-app/main/default/classes/ContractTriggerHandler.cls#L55) | El Status **no cambió** en ese update → no hace nada. **Sin recursión**, sin variable estática. | T1 · before update |
| 7 | (no se ve) | CPQ inserta una **Renewal Quote temporal** (para calcular los precios de la Opportunity) → `QuoteTrigger`. | [QuoteTrigger.trigger:14-15](../../force-app/main/default/triggers/QuoteTrigger.trigger#L14-L15), [:18-19](../../force-app/main/default/triggers/QuoteTrigger.trigger#L18-L19) | `before insert` (DEV #1): nace en Draft → nada. `after insert` → `afterInsert`. | T1 · before / **after insert** de Quote |
| 8 | (no se ve) | → **filtro de la Quote temporal** | [QuoteTriggerHandler.cls:150-159](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L150-L159), [:166-171](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L166-L171), [:179-186](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L179-L186) | Es `Type = Renewal` → pasa el primer filtro → **1 SOQL** sube Quote → Opportunity → Contract y lee `SBQQ__RenewalQuoted__c`: está en **false** (nadie pidió una Quote) → lista vacía → `return`. **No hay email.** | T1 · after insert |
| 9 | (unos segundos después) | CPQ corre su `QueueableCalculatorService`. | — (código de CPQ) | Calcula los precios de la Renewal Opportunity (215 × 120 = **25.800**) y **borra** la Quote temporal. | **async** de CPQ |
| 10 | Refresco el Contract: *Renewal Forecast* tildado, *Renewal Opportunity* con link. Abro la Opportunity: **Prospecting**, 215, 25.800. **No llegó ningún email.** | — | — | Resultado de la Parte 1. | — |

> Paso 7, detalle: además de la temporal, CPQ inserta **otra** Renewal Quote y la deshace en la misma transacción (rollback interno). Ese rollback también descarta cualquier email encolado. Ver [DEV3.md §2, "Hallazgo"](../code-review/DEV3.md#hallazgo-después-de-la-primera-prueba-la-renewal-quote-temporal-de-cpq).

### Por qué prender el flag nativo de CPQ y no crear la Opportunity a mano

| | **Tildar `SBQQ__RenewalForecast__c` (elegido)** | **Crear Opportunity + productos a mano** |
|---|---|---|
| Cantidades con Amendments | CPQ combina cada Subscription con su original: 125 + 100 − 10 = **una línea de 215** | Tendría que agrupar las Subscriptions por `SBQQ__RevisedSubscription__c` y sumar yo |
| Precios, Pricebook, fechas, co-terminación | Los resuelve CPQ (su calculador) | Reimplementar la lógica de precios de CPQ |
| Vínculo con el Contract (`SBQQ__RenewedContract__c`, `SBQQ__RenewalOpportunity__c`) | Lo completa CPQ, y la Parte 2 lo necesita para encontrar la Opportunity | A mano, con riesgo de que CPQ no la reconozca como "su" renewal (y después cree otra) |
| Código nuestro | **1 línea** en un before update | Una clase entera, con SOQL y DML en after |
| Es lo mismo que | El checkbox *Renewal Forecast* de la UI de CPQ | — |

**Qué pasaría con la otra opción:** mucho más código para defender y probar, y fácil de equivocar justo en lo que el requirement pide ("accurately forecast"). Además, si CPQ no reconoce la Opportunity, al tildar *Renewal Quoted* crearía una segunda. Lo verificamos antes de programar (Paso 0 sobre el Contract 00000107, [DEV3.md §2](../code-review/DEV3.md#lo-que-verificamos-en-el-org-antes-de-programar-paso-0-contract-00000107)).

### Parte 2: 30 días antes del fin → Renewal Quote + Opportunity + email

Cada `execute` del Batch es **su propia transacción** (T2), con sus propios governor limits.

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | *Setup → Scheduled Jobs*: **Renewal Quote Generation - Nightly**, próxima a las 3:00. (En la demo: **Plan B**, ver abajo.) | A las 3:00 Salesforce llama al Scheduler. | [RenewalQuoteScheduler.cls:26-28](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L26-L28) | Sin lógica: `Database.executeBatch( new RenewalQuoteBatch(), BATCH_SIZE )`, con `BATCH_SIZE = 1` ([:20](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L20)). Cron `0 0 3 * * ?` ([:16](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L16)). | **async** · Scheduled |
| 2 | (no se ve) | `start` del Batch | [RenewalQuoteBatch.cls:54-65](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L54-L65) | **1 query** con la ventana: `Status = Activated`, `RenewalQuoted = false`, `hoy <= EndDate <= hoy + 30`. Hoy trae solo el 00000110 (una vez activado). | async · Batch `start` |
| 3 | (no se ve) | `execute` (1 vez por Contract) | [RenewalQuoteBatch.cls:74-77](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L74-L77) | Primero `requestRenewalQuotes`, después `updateRenewalOpportunityStage` con los que salieron bien. | **T2** · Batch `execute` |
| 4 | (no se ve) | → pedirle la Quote a CPQ | [RenewalQuoteBatch.cls:97-102](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L97-L102) | Tilda `SBQQ__RenewalForecast__c` (red de seguridad) y `SBQQ__RenewalQuoted__c` → **1 DML** `Database.update( lista, false )`. | T2 |
| 5 | (no se ve) | Dentro de ese update: `ContractTrigger`. | [ContractTriggerHandler.cls:55](../../force-app/main/default/classes/ContractTriggerHandler.cls#L55) | El Status no cambió → nada. | T2 · before update |
| 6 | (no se ve) | Dentro del mismo update: **`SBQQ.ContractAfter`**. | — (código de CPQ) | Ve `RenewalQuoted = true` → crea la **Renewal Quote** (Type Renewal, Draft, **Primary**, Owner = el de la Opportunity, 01/11/2026 → 31/10/2027, 1 línea de 215). | T2 · after update (de CPQ) |
| 7 | (no se ve) | CPQ inserta la Quote → `QuoteTrigger`. | [QuoteTrigger.trigger:18-19](../../force-app/main/default/triggers/QuoteTrigger.trigger#L18-L19) → [QuoteTriggerHandler.cls:73-75](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L73-L75) | `after insert` porque el link necesita el **Id** (en before insert no existe). | T2 · **after insert** de Quote |
| 8 | (no se ve) | → filtros antes y después de la SOQL | [QuoteTriggerHandler.cls:150-159](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L150-L159), [:166-171](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L166-L171), [:179-186](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L179-L186) | Es Renewal → **1 SOQL** (nombres + flag del Contract). Ahora el flag está en **true** (lo acaba de tildar el Batch, misma transacción) → la Quote **sí** pasa. | T2 · after insert |
| 9 | (no se ve) | → armar el email | [QuoteTriggerHandler.cls:162](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L162), [:188-197](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L188-L197), [:225-235](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L225-L235) | `orgUrl` una sola vez, afuera del loop. `setTargetObjectId( OwnerId )` (no cuenta para el límite diario), `setSaveAsActivity( false )`, asunto *"Renewal Quote created: Q-xxxxx"*, cuerpo de `buildEmailBody` con `orgUrl + '/' + Id`. | T2 · after insert |
| 10 | (no se ve) | → enviar | [QuoteTriggerHandler.cls:199-216](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L199-L216) | **1** `Messaging.sendEmail( lista, false )` dentro de **try/catch**. Si falla → `Error_Log__c`. Nunca se rompe el save en el que CPQ crea la Quote. El email sale recién cuando la transacción hace commit. | T2 · after insert |
| 11 | (no se ve) | CPQ encola su `QueueableCalculatorService` para la Quote nueva. | — (código de CPQ) | **Este es el único Queueable que se puede encolar desde un `execute` de Batch.** Por eso las tandas son de 1. | T2 → async de CPQ |
| 12 | (no se ve) | Vuelve a `requestRenewalQuotes`. | [RenewalQuoteBatch.cls:104-112](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L104-L112) | Lee los `SaveResult` por posición: los que salieron bien van al `Set<Id>`; los que fallaron → `ErrorLogUtil.saveLogsForFailedResults` (el flag queda en false → se reintenta la noche siguiente). | T2 |
| 13 | (no se ve) | → mover la etapa | [RenewalQuoteBatch.cls:120-143](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L120-L143) | Si el Set está vacío → `return` antes de la SOQL ([:122-124](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L122-L124)). **1 SOQL**: Opportunities con `SBQQ__RenewedContract__c IN :set` **y `StageName = 'Prospecting'`** → `Proposal/Price Quote` → **1 DML** + Error Logs. | T2 |
| 14 | (no se ve) | `finish` | [RenewalQuoteBatch.cls:83-85](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L83-L85) | Vacío a propósito (la interfaz lo exige). | async |
| 15 | *Apex Jobs*: `RenewalQuoteBatch` **Completed**, 1 ítem, 0 errores. Contract: *Renewal Quoted* tildado. Opportunity: **Proposal/Price Quote**, Primary Quote = la nueva. Quote: Renewal, 215. **Inbox: UN email** con el link → abre la Quote. *Error Logs*: vacía. | — | — | Resultado de la Parte 2. | — |

### El bug de la Q-00090 (la Quote temporal de CPQ) y cómo lo resolvimos

- **Qué vimos:** en la primera prueba E2E (Contract 00000109) llegaron **dos** emails: Q-00092 (bien) y **Q-00090**, con un link que no abría nada: la Quote estaba en la papelera.
- **Qué era:** al tildar *Renewal Forecast* (activación), CPQ crea una **Renewal Quote temporal** para calcular los precios de la Opportunity y la **borra** cuando termina su Queueable. Nadie la borró a mano (mismo patrón en Q-00083 y Q-00106, [tabla en DEV3.md §2](../code-review/DEV3.md#hallazgo-después-de-la-primera-prueba-la-renewal-quote-temporal-de-cpq)).
- **Por qué costaba filtrarla:** en el `after insert` la temporal es **idéntica** a una real (Renewal, Primary, Draft, sin calcular). Por sus propios campos no hay forma de distinguirlas.
- **La solución (opción A):** mirar al **Contract**, no a la Quote. Solo se avisa si el Contract tiene `SBQQ__RenewalQuoted__c = true`, o sea, si alguien **pidió** la Quote (el Batch o un usuario). En la activación ese flag está en false; en el Batch, en true. Se lee en la **misma query** que ya existía, subiendo dos lookups: **0 queries extra** ([QuoteTriggerHandler.cls:166-186](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L166-L186)).
- **`== true` y no `if ( flag )`:** si la Opportunity no tiene Contract, el valor llega `null`; `null == true` da false (no manda) y no tira excepción.
- **Verificado:** Contract 00000111 → activación con **0** emails, Batch con **1** (Q-00108). Lo confirmaste en Gmail. Test: `renewalQuoteNotRequestedNoEmailTest`.
- **Descartadas:** mandar el email desde el Batch (dejaría de avisar por las Quotes pedidas a mano) y un Queueable diferido que revise si la Quote sigue viva (carrera de tiempos y no hay cupo de Queueable en el Batch).

### Por qué el Batch corre con scope 1

1. **El cupo de Queueables:** desde un `execute` de Batch se puede encolar **1** Queueable. CPQ encola **uno por cada Renewal Quote** (su calculador). Con 2 Contracts en la tanda, el segundo rompería con *"Too many queueable jobs"*.
2. **Los límites de CPQ:** los tests bulk mostraron que generar muchas renovaciones juntas rompe `SBQQ: Too many SOQL queries: 101` **dentro del código de CPQ** (el prefijo `SBQQ:` lo dice). Nuestro código usa 1 query por paso.
3. **Con tanda de 1, cada Contract tiene sus propios governor limits:** si uno falla, no arrastra a los demás.
4. **¿Y la velocidad?** Entran pocos Contracts por noche (los que llegan a la ventana). No es un problema.
- El código **sigue bulkificado** (lista, 1 update, `Set<Id>`, 1 query): por eso el test bulk lo corre con tanda de 200 y pasa. El "1" es una decisión de cómo se **llama** al Batch ([RenewalQuoteScheduler.cls:18-20](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L18-L20)), no de cómo está escrito.

### El cambio de etapa de la Opportunity (solo desde Prospecting)

- **Qué:** "the Renewal Opportunity to be updated" = `StageName` de **Prospecting** a **Proposal/Price Quote**. CPQ además le pone la Quote como Primary y sincroniza productos y Amount; la etapa no la toca (verificado).
- **Dónde:** en el Batch, **después** de que CPQ creó la Quote y **solo** para los Contracts cuyo update salió bien (el `Set<Id>` del paso 12).
- **Por qué solo desde Prospecting** (está en el `WHERE`, [RenewalQuoteBatch.cls:132](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L132)): si un vendedor ya la movió a Negotiation/Review, la pisaríamos y la Opportunity **retrocedería**. Prospecting es la etapa con la que la crea CPQ: si sigue ahí, nadie la tocó.
- **Por qué no en el after insert de la Quote:** correría dentro del insert de CPQ, antes de que existan las líneas, y mezclaría el email con cambios de datos.

### PLAN B para la demo: correr el Batch a mano sin esperar a las 3:00

1. **Antes de la demo:** **no** actives el 00000110 la noche anterior. Si queda Activated antes de las 3:00 (10:00 UTC), el job real lo procesa solo y en la demo ya vas a encontrar la Quote creada. (Al 07/10/2026 está en Draft, sin flags, y es el único Contract en la ventana.)
2. Hacé la **Parte 1** en vivo (activar) y **esperá ~5 segundos** a que termine el cálculo de CPQ (la Opportunity muestra 25.800).
3. *(Opcional)* Para mostrar qué va a procesar, en *Developer Console → Query Editor*:
   ```sql
   SELECT ContractNumber, Status, EndDate, SBQQ__RenewalQuoted__c
   FROM Contract
   WHERE Status = 'Activated' AND SBQQ__RenewalQuoted__c = false
   AND EndDate >= TODAY AND EndDate <= NEXT_N_DAYS:30
   ```
   Tiene que aparecer solo el **00000110** (es la misma ventana que el `start` del Batch).
4. Abrí el inbox del Owner (frandev → fpistone@firstchairservices.com) **antes** de correr el Batch.
5. *Developer Console → Debug → Open Execute Anonymous Window* y ejecutá:
   ```apex
   Database.executeBatch( new RenewalQuoteBatch(), RenewalQuoteScheduler.BATCH_SIZE );
   ```
   Es **exactamente** lo que hace el Scheduler a las 3:00 ([RenewalQuoteScheduler.cls:27](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L27)), con el mismo tamaño de tanda (1). No cambia nada del job programado.
6. *Setup → Apex Jobs*: `RenewalQuoteBatch` **Completed** (1/1, 0 errores). Puede aparecer un `QueueableCalculatorService` de CPQ: es el cálculo de la Quote nueva.
7. Seguí con el paso 15 de la tabla: Contract, Opportunity, Quote, email, Error Logs.
8. **Si algo falla en vivo:** mostrar la evidencia ya generada: Contract **00000109** (Q-00092) o **00000111** (Q-00108). Fecha límite del 00000110: **31/10/2026** (después sale de la ventana; los scripts `scripts/apex/dev3-1/2/3-*.apex` arman otro).

---

## 4. Qué decir (guion mientras muestro el código)

1. "El requirement tiene dos momentos: cuando se **activa** el Contract, que es un guardado y lo resuelvo con un trigger, y **30 días antes del fin**, que es el calendario que avanza y lo resuelvo con un job nocturno."
2. "En los dos casos no creo registros a mano: prendo los flags nativos de CPQ, *Renewal Forecast* y *Renewal Quoted*, y CPQ arma la Opportunity y la Quote con los Amendments incluidos: acá 125 + 100 − 10 da una línea de 215."
3. "La activación está en **before update**: comparo con `Trigger.oldMap`, y si el Status pasó a Activated tildo el flag en memoria. Sin SOQL, sin DML y sin recursión, porque cuando CPQ vuelve a actualizar el Contract el Status ya no cambia."
4. "El Batch corre a las 3:00 con tandas de 1, porque CPQ encola un Queueable por cada Renewal Quote y desde un Batch solo se puede encolar uno. Busca la ventana de hoy a hoy + 30, así que si una noche falla, la siguiente lo toma, y el flag evita procesarlo dos veces. Después pasa la Opportunity a Proposal, solo si sigue en Prospecting."
5. "El email está en el **after insert** de la Quote, porque el link necesita el Id. En la primera prueba nos llegó un email con un link muerto: era una Quote temporal que CPQ crea y borra al activar. Lo resolvimos mirando el flag del Contract en la misma query: solo avisamos si alguien pidió la Quote."
6. "El envío está en try/catch, porque corre dentro del save en el que CPQ crea la Quote: un error de email no puede deshacer la renovación. Los errores van a `Error_Log__c`."

---

## 5. Decisiones y alternativas (resumen)

- **Flags nativos de CPQ** en lugar de crear Opportunity/Quote a mano; Parte 1 en **before update** (sin before insert, porque Salesforce no deja insertar un Contract Activated) en lugar de after + `update` extra.
- **Scheduler + Batch de a 1** con ventana `hoy <= EndDate <= hoy + 30` (y no `= hoy + 30` exacto) y el flag como marca de procesado; etapa movida **en el Batch, solo desde Prospecting**.
- **Email en el after insert de Quote**, armado en Apex, `setTargetObjectId`, try/catch, filtrado por el flag del Contract (opción A del bug de la Q-00090).

Detalle con "por qué sí / por qué no / qué pasaría" de cada una, incluidas las decisiones chicas: [DEV3.md §2](../code-review/DEV3.md#2-diseño-elegido).

### Dónde aparecen los patrones base en este DEV

Explicación general de cada patrón: [00-patrones-base.md](00-patrones-base.md).

| Patrón | Dónde aparece en el DEV #3 |
|---|---|
| **Un trigger por objeto → handler** | [ContractTrigger.trigger:11-15](../../force-app/main/default/triggers/ContractTrigger.trigger#L11-L15) (nuevo). En Quote **no** se creó otro trigger: se sumó `after insert` al existente del DEV #1 ([QuoteTrigger.trigger:13](../../force-app/main/default/triggers/QuoteTrigger.trigger#L13), [:18-19](../../force-app/main/default/triggers/QuoteTrigger.trigger#L18-L19)). Ver [00-patrones-base §1](00-patrones-base.md#1-un-solo-trigger-por-objeto-sin-lógica-trigger--handler). |
| **`Trigger.oldMap` / detectar el cambio real** | [ContractTriggerHandler.cls:53-56](../../force-app/main/default/classes/ContractTriggerHandler.cls#L53-L56). Es lo que corta la recursión cuando CPQ, el DEV #4 o el propio Batch actualizan el Contract. Ver [00-patrones-base §2](00-patrones-base.md#2-triggernew-triggeroldmap-y-cómo-detectamos-un-cambio-real). |
| **Contexto correcto (before = mismo registro, after = necesito el Id)** | Before: [ContractTriggerHandler.cls:58](../../force-app/main/default/classes/ContractTriggerHandler.cls#L58), asignación en memoria. After: [QuoteTriggerHandler.cls:153](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L153) y el link en [:232](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L232) usan `Id`. Ver [00-patrones-base §3](00-patrones-base.md#3-before-vs-after-cuándo-uso-cada-uno). |
| **Bulkificación: Set, 1 SOQL, nada en loops** | Batch: **1** update ([RenewalQuoteBatch.cls:102](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L102)), `Set<Id>` ([:105](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L105)), **1** query + **1** update de Opportunities ([:128-141](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L128-L141)). Email: `Set<Id>` ([QuoteTriggerHandler.cls:150](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L150)), **1** query ([:166-171](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L166-L171)), **1** `sendEmail` para todas ([:201](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L201)). Ver [00-patrones-base §4](00-patrones-base.md#4-bulkificación-setsmaps-soql-y-dml-fuera-de-loops). |
| **Condicional antes de la SOQL** | [QuoteTriggerHandler.cls:157-159](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L157-L159) (la mayoría de las Quotes no son Renewal: 0 queries) y [RenewalQuoteBatch.cls:122-124](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L122-L124). |
| **WHERE para reducir volumen** | [RenewalQuoteBatch.cls:60-63](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L60-L63) (la ventana) y [:131-132](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L131-L132) (solo Prospecting). |
| **Relaciones lookup en la SOQL** | [QuoteTriggerHandler.cls:167-168](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L167-L168): sube Quote → Opportunity → Contract en la misma query. |
| **Constantes / DRY** | `STATUS_ACTIVATED` definida **una** vez ([ContractTriggerHandler.cls:24](../../force-app/main/default/classes/ContractTriggerHandler.cls#L24)) y reusada por el Batch ([RenewalQuoteBatch.cls:60](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L60)). `ErrorLogUtil.saveLogsForFailedResults` compartido con el DEV #2 y el DEV #4 ([:111](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L111), [:142](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L142)). |
| **Async (Módulo 4): Scheduled + Batch** | `Schedulable` que solo delega ([RenewalQuoteScheduler.cls:11](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L11), [:26-28](../../force-app/main/default/classes/RenewalQuoteScheduler.cls#L26-L28)); `Database.Batchable` con `start`/`execute`/`finish` ([RenewalQuoteBatch.cls:36](../../force-app/main/default/classes/RenewalQuoteBatch.cls#L36)), sin `Database.Stateful`. |
| **Sin fallar en silencio** | `Database.update( lista, false )` + Error Log en el Batch; try/catch + Error Log en el email ([QuoteTriggerHandler.cls:199-216](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L199-L216)). |

---

## 6. Tests

Todos usan `@testSetup`, `Test.startTest()/stopTest()`, la `TestDataFactory` (`buildContracts`, `buildRenewalOpportunities`) y asserts con mensaje. Notas clave:

- **Batch en test:** se lanza con tamaño **200** (`BULK_SIZE`), no con 1: en un test el `execute()` corre **una sola vez**, así que con 1 solo procesaría un Contract. El `stopTest()` fuerza a que el Batch corra; los asserts van después.
- **Email en test:** no sale, pero `Limits.getEmailInvocations()` cuenta las llamadas a `sendEmail`; se lee **antes** del `stopTest()`.
- **`SBQQ.TriggerControl.disable()`** (fuera del curso) **solo** en los 2 bulk: sin eso, el código de CPQ rompe `SBQQ: Too many SOQL queries` al generar 200 renovaciones. El bulk mide **nuestra** bulkificación ([DEV3.md §4](../code-review/DEV3.md#sbqqtriggercontroldisable-solo-en-2-tests-bulk)).

| Tipo | Caso | Archivo:método |
|---|---|---|
| **Positivo (P1)** | Draft → Activated → Renewal Forecast = true | [ContractTriggerHandlerTest.cls:24](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L24) `activationSetsRenewalForecastTest` |
| **Bulk 200 (P1)** | 200 Contracts activados juntos → 200 con el flag | [ContractTriggerHandlerTest.cls:47](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L47) `activationBulkTest` |
| **Negativo (P1)** | Draft → In Approval Process → no se tilda | [ContractTriggerHandlerTest.cls:71](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L71) `otherStatusDoesNotSetForecastTest` |
| **Negativo (P1)** | Se edita otro campo → no se tilda | [ContractTriggerHandlerTest.cls:87](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L87) `otherFieldUpdateDoesNotSetForecastTest` |
| **Negativo (P1, recursión)** | Ya activado + otro campo → no se reprocesa | [ContractTriggerHandlerTest.cls:104](../../force-app/main/default/classes/ContractTriggerHandlerTest.cls#L104) `alreadyActivatedNotReprocessedTest` |
| **Positivo (P2)** | Vence en 19 días → Renewal Quoted + Forecast | [RenewalQuoteBatchTest.cls:33](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L33) `contractInWindowQuotedTest` |
| **Borde (P2)** | Hoy y 30 entran; 31 y ayer no | [RenewalQuoteBatchTest.cls:52](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L52) `windowBoundaryTest` |
| **Negativo (P2)** | Draft en la ventana → no | [RenewalQuoteBatchTest.cls:76](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L76) `draftContractNotQuotedTest` |
| **Negativo (P2)** | Evergreen (sin fin) → no | [RenewalQuoteBatchTest.cls:91](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L91) `evergreenContractNotQuotedTest` |
| **Positivo (P2)** | Activado sin Forecast → el Batch tilda los dos | [RenewalQuoteBatchTest.cls:109](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L109) `missingForecastSafetyNetTest` |
| **Positivo + negativo (P2)** | Prospecting → Proposal; Negotiation/Review no se toca | [RenewalQuoteBatchTest.cls:130](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L130) `opportunityStageUpdatedTest` |
| **Negativo (P2)** | Ya con Renewal Quoted → no se reprocesa | [RenewalQuoteBatchTest.cls:154](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L154) `alreadyQuotedNotReprocessedTest` |
| **Bulk 200 (P2)** | 200 Contracts → 200 Quoted + 200 Opportunities en Proposal | [RenewalQuoteBatchTest.cls:180](../../force-app/main/default/classes/RenewalQuoteBatchTest.cls#L180) `bulkTest` |
| **Positivo (Scheduler)** | Cron `0 0 3 * * ?` + lanza 1 Batch (nombre de job de test) | [RenewalQuoteSchedulerTest.cls:14](../../force-app/main/default/classes/RenewalQuoteSchedulerTest.cls#L14) `scheduleNightlyJobTest` |
| **Positivo (email)** | Renewal Quote pedida → 1 envío, 0 Error Logs | [QuoteTriggerHandlerTest.cls:193](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L193) `renewalQuoteSendsEmailTest` |
| **Bulk 200 (email)** | 200 Renewal Quotes → **1** envío | [QuoteTriggerHandlerTest.cls:210](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L210) `renewalQuoteBulkEmailTest` |
| **Negativo (email)** | Quote que no es Renewal → 0 envíos | [QuoteTriggerHandlerTest.cls:226](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L226) `nonRenewalQuoteNoEmailTest` |
| **Negativo (email, bug Q-00090)** | Renewal Quote con Contract `RenewalQuoted = false` (la temporal) → 0 envíos | [QuoteTriggerHandlerTest.cls:241](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L241) `renewalQuoteNotRequestedNoEmailTest` |

Cobertura: `ContractTrigger`, `ContractTriggerHandler`, `RenewalQuoteScheduler` y `QuoteTrigger` **100%**; `RenewalQuoteBatch` **95%** y `QuoteTriggerHandler` **91%** (las líneas sin cubrir son ramas de error que no se pueden forzar en un test, como hacer fallar `sendEmail`). Build Tracker y detalle: [DEV3.md §9](../code-review/DEV3.md#9-tests-cobertura-y-build-tracker).

---

## 7. Edge cases cubiertos y supuestos

**Edge cases** (tabla completa con su test en [DEV3.md §6](../code-review/DEV3.md#6-edge-cases)):

- Status que cambia a otro valor, o se edita otro campo → no se tilda nada.
- Recursión: CPQ, el DEV #4 o el Batch actualizan el Contract → el Status no cambió → nada.
- Insertar un Contract ya Activated → Salesforce no lo permite (`FAILED_ACTIVATION`): por eso no hay before insert.
- Bordes de la ventana: hoy y +30 entran; +31, ayer, Draft y evergreen no.
- Contract activado antes del trigger (sin Forecast) → el Batch tilda los dos flags (red de seguridad).
- Ya procesado (`RenewalQuoted = true`) → no vuelve a entrar. El job falla una noche → la siguiente lo toma.
- Opportunity que un vendedor ya avanzó → no se toca.
- Quote que no es Renewal, o Renewal **no pedida** (la temporal de CPQ) → sin email.
- 200 Contracts / 200 Quotes → 1 update, 1 query, 1 `sendEmail`.
- Falla un update o un email → Error Log; la Quote de CPQ se crea igual.

**Supuestos** (detalle en [DEV3.md §5](../code-review/DEV3.md#5-supuestos-y-decisiones)):

- "Activated" = el Status **cambia** a Activated; la activación es **manual** (no se tocó el IC).
- "30 días antes" = `hoy <= EndDate <= hoy + 30`; "hoy" en la zona del usuario que programó el job (America/Los_Angeles).
- "Actualizar la Opportunity" = etapa Prospecting → Proposal/Price Quote.
- El Owner de la Quote lo pone CPQ (el de la Opportunity). Email en inglés, texto plano.
- Limitaciones conocidas (activación masiva rompe límites de CPQ, caso gris de los dos flags en el mismo save, dependencia del comportamiento interno de CPQ): [DEV3.md §10](../code-review/DEV3.md#10-limitaciones-conocidas-y-pendientes-de-qa).

---

## 8. Cinco preguntas probables del revisor

**1. ¿Por qué tildaste los flags de CPQ en vez de crear la Opportunity y la Quote vos?**
Porque CPQ ya sabe armar una renovación: combina los Amendments (125 + 100 − 10 = 215), aplica precios, vincula todo con el Contract y deja la Quote Primary. Es lo mismo que hace su checkbox en la UI. Reimplementarlo sería mucho código y fácil de equivocar. Lo probamos en el org antes de programar.

**2. ¿Por qué la activación está en before update y no en after?**
Porque solo cambio un campo del mismo Contract: en before lo asigno en memoria y se guarda en el mismo save, sin DML. En el after de ese save, el trigger de CPQ ve el flag y crea la Opportunity. En after necesitaría un `update` extra del Contract, que vuelve a disparar todos los triggers.

**3. ¿Por qué el Batch corre de a 1 si tu código está bulkificado?**
Por CPQ, no por nuestro código: CPQ encola un Queueable por cada Renewal Quote y desde un `execute` de Batch solo se puede encolar uno; además su generación rompe el límite de queries con volumen. El código sí está bulkificado: el test bulk lo corre con 200 y pasa. Por noche entran pocos Contracts.

**4. ¿Cómo evitás mandar emails de Quotes que no corresponden?**
Primero filtro por `Type = Renewal` antes de la query. Después miro el flag `RenewalQuoted` del Contract en la misma query: solo aviso si alguien pidió la Quote. Así descarto la Quote temporal que CPQ crea y borra al activar, que en la primera prueba nos mandó un email con un link muerto (Q-00090).

**5. ¿Qué pasa si el job no corre una noche, o si un vendedor ya avanzó la Opportunity?**
La ventana es "30 días o menos" y no "exactamente 30", así que la noche siguiente lo procesa igual; el flag `RenewalQuoted` evita hacerlo dos veces. Y la etapa solo se cambia si la Opportunity sigue en Prospecting: si un vendedor la movió, no la pisamos para no hacerla retroceder.

Más preguntas (15 en total): [DEV3.md §7](../code-review/DEV3.md#7-preguntas-probables-del-code-review).
