# DEV #1 · Paso a paso para la defensa (vencimiento de la Quote + recall nocturno)

> **Para qué sirve este documento:** es la guía para **mostrar y explicar** el DEV #1 en el Code Review, en el orden en que se ejecuta. El detalle completo (diseño, bloques, edge cases, 14 preguntas, Build Tracker) está en [`docs/code-review/DEV1.md`](../code-review/DEV1.md); acá no se repite, se referencia. Los patrones que se repiten en todos los DEV están en [`00-patrones-base.md`](00-patrones-base.md).
>
> Los números de línea son del commit `425d462` (07/10/2026). Si el código cambia, revisarlos.

---

## 1. Requirement en 2 líneas (palabras de vendedor)

- **Parte A:** "Cuando me aprueban una Quote, la oferta vale 30 días **desde el día en que la aprobaron**, no desde que armé el borrador."
- **Parte B:** "Si mi Quote se queda esperando aprobación hasta que vence y todavía no gané la venta, el sistema retira sola esa aprobación pendiente, y la Quote me vuelve a Draft para corregirla y mandarla de nuevo."

Texto original y tabla de partes (A)…(E): [DEV1.md §1](../code-review/DEV1.md#1-qué-pide-el-requirement).

---

## 2. Flujo lógico (sin código)

1. Aprobar una Quote = que su campo **Status pase a Approved**. Lo hace un *field update* del Approval Process, que es un update y por eso **dispara el trigger**.
2. En ese mismo guardado, **antes** de que se escriba en la base, el trigger le pone **vencimiento = hoy + 30**. Es un campo del mismo registro, así que no hace falta ningún DML.
3. Solo actúa si el Status **cambió** a Approved (nuevo vs viejo). Editar una Quote ya aprobada no le alarga el vencimiento.
4. "La Quote venció" no es un guardado, es el calendario que avanza: **ningún trigger se entera**. Por eso hay un job que corre **todas las noches a la 1:00**.
5. El job busca Quotes **In Review** (aprobación pendiente), con vencimiento `<= hoy`, con Opportunity y **no ganada**.
6. A esas les hace **recall** (lo mismo que el botón "Recall"): Salesforce las pasa a **Draft** y las desbloquea. Las ya aprobadas no se tocan, porque no hay nada pendiente que retirar.

---

## 3. Cronología demo → código

### Parte A: aprobar la Quote (síncrono, todo en el mismo save)

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| A1 | Abro una Quote en **Draft** (Net 30, sin descuento) y anoto su *Expiration Date* (la de CPQ: creación + 30). | Nada nuestro. Se creó antes; en su insert corrió `beforeInsert`, pero nació en Draft. | [QuoteTriggerHandler.cls:86-94](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L86-L94) | `setExpirationDateOnInsert`: solo junta las que **nacen** Approved. Esta no. | before insert |
| A2 | Clic en **Submit for Approval**. | El Approval Process (`Auto_Approval`) hace el field update `Set_Quote_Status_In_Review` → **update** de la Quote. | [QuoteTrigger.trigger:16-17](../../force-app/main/default/triggers/QuoteTrigger.trigger#L16-L17) | El trigger ve `isBefore && isUpdate` y delega en `beforeUpdate( Trigger.new, Trigger.oldMap )`. | before update |
| A3 | (no se ve) | → handler | [QuoteTriggerHandler.cls:64-66](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L64-L66) | Método de entrada: solo llama a `setExpirationDateOnUpdate`. | before update |
| A4 | (no se ve) | → lógica | [QuoteTriggerHandler.cls:105-111](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L105-L111) | Compara con `oldMap`: Draft → **In Review**. Cambió, pero **no** a Approved → la lista queda vacía. | before update |
| A5 | (no se ve) | → regla | [QuoteTriggerHandler.cls:124-126](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L124-L126) | `setExpirationDate` recibe la lista vacía y sale con `return`. | before update |
| A6 | (con `Auto_Approval` es inmediato; con `Quote_Approval_V2` el aprobador hace clic en **Approve**) | Field update `Set_Quote_Status_Approved` (+ template Final) → **otro update** de la Quote. | [QuoteTrigger.trigger:16-17](../../force-app/main/default/triggers/QuoteTrigger.trigger#L16-L17) | Mismo camino: trigger → `beforeUpdate`. | before update |
| A7 | (no se ve) | → lógica | [QuoteTriggerHandler.cls:106-110](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L106-L110) | `oldQuoteByIdMap.get( newQuote.Id )` trae la versión vieja: In Review → **Approved**. `statusChanged = true` y el nuevo es Approved → entra a `approvedQuoteList`. | before update |
| A8 | (no se ve) | → regla | [QuoteTriggerHandler.cls:127-130](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L127-L130) | Calcula `Date.today().addDays( 30 )` **una vez, afuera del loop**, y lo asigna en memoria a cada Quote. 0 SOQL, 0 DML. | before update |
| A9 | Refresco la Quote: **Approved**, con candado, *Expiration Date* = **hoy + 30**. | Salesforce guarda el registro con la fecha que pusimos (es el mismo save). | — | El cambio "viaja" en `Trigger.new`: lo que se asigna en before se guarda solo. | fin del save |

### Parte B: la Quote vence esperando aprobación (asíncrono, de noche)

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| B1 | Creo una Quote en una Opportunity **abierta**, con **Payment Terms = Net 60**, y le pongo *Expiration Date* = **ayer**. | Update de la Quote → trigger. | [QuoteTriggerHandler.cls:105-111](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L105-L111) | El Status no cambió → no hace nada (la fecha a mano se respeta). | before update |
| B2 | **Submit for Approval** → Status **In Review**, candado, aparece en "Items to Approve" de Finance. | `Quote_Approval_V2`: field update In Review + crea el **work item** (`ProcessInstanceWorkitem`). | [QuoteTriggerHandler.cls:105-111](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L105-L111) | Pasó a In Review, no a Approved → no hace nada. | before update |
| B3 | En la demo: *Execute Anonymous* → `Database.executeBatch( new QuoteExpirationBatch() );`. En la vida real: **1:00 AM**, job "Quote Expiration Recall - Nightly". | Salesforce llama al Scheduler a la hora del cron. | [QuoteExpirationScheduler.cls:18](../../force-app/main/default/classes/QuoteExpirationScheduler.cls#L18), [:24-26](../../force-app/main/default/classes/QuoteExpirationScheduler.cls#L24-L26) | `CRON_EXPRESSION = '0 0 1 * * ?'`. `execute` **solo** lanza el Batch (sin lógica propia). | async (Scheduled) |
| B4 | (se ve en Setup → Apex Jobs) | `start` del Batch, una vez. | [QuoteExpirationBatch.cls:42-51](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L42-L51) | **Una** query: `In Review` + `ExpirationDate <= TODAY` + con Opportunity + `IsWon = false`. Devuelve un `QueryLocator`. | async (Batch, start) |
| B5 | (no se ve) | Salesforce parte el resultado en tandas de 200 y llama a `execute` por tanda. | [QuoteExpirationBatch.cls:58-60](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L58-L60) | Solo delega en `recallPendingApprovals`. Cada tanda tiene **sus propios governor limits**. | async (Batch, execute) |
| B6 | (no se ve) | → lógica | [QuoteExpirationBatch.cls:78-81](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L78-L81) | Junta los Ids de la tanda en un `Set<Id>`. | async |
| B7 | (no se ve) | → **1 SOQL** | [QuoteExpirationBatch.cls:87-98](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L87-L98) | Trae los work items pendientes de esas Quotes y arma un `ProcessWorkitemRequest` con acción **`'Removed'`** por cada uno. Anota en una lista paralela de qué Quote es cada request. | async |
| B8 | (no se ve) | → corte | [QuoteExpirationBatch.cls:102-104](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L102-L104) | Si no hay work items (ej. "In Review" puesto a mano), `return`. | async |
| B9 | (no se ve) | → **1 llamada para toda la tanda** | [QuoteExpirationBatch.cls:106](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L106) | `Approval.process( recallRequestList, false )`: todos los recalls juntos; si uno falla, los demás siguen. | async |
| B10 | (no se ve) | Salesforce corre la **Recall Action** del proceso: field update `Set_Quote_Status_Draft` → update de la Quote → **nuestro trigger otra vez**. | [QuoteTriggerHandler.cls:105-111](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L105-L111) | In Review → **Draft**: no es Approved → no hace nada. **No hay recursión.** | before update (dentro del Batch) |
| B11 | (no se ve) | → errores | [QuoteExpirationBatch.cls:109-116](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L109-L116) | Recorre los resultados **por posición**; si alguno falló, arma un Error Log y los guarda todos con **un** insert (`ErrorLogUtil.saveLogs`). | async |
| B12 | (no se ve) | `finish` | [QuoteExpirationBatch.cls:66-68](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L66-L68) | Vacío a propósito (la interfaz lo exige). | async (Batch, finish) |
| B13 | Refresco la Quote: **Draft**, sin candado; *Approval History* → **Recalled** con el comentario "Recalled automatically: …"; ya no figura en "Items to Approve". Tab **Error Logs** vacía. | — | [QuoteExpirationBatch.cls:32](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L32) | El comentario que se ve en el historial es la constante `RECALL_COMMENT`. | — |

Pasos de demo con más detalle y evidencia real en el org (Q-00061, Q-00072 a 78, Q-00079): [DEV1.md §8](../code-review/DEV1.md#8-cómo-se-prueba-en-la-demo).

---

## 4. Qué decir (guion mientras muestro el código)

1. "El requirement tiene dos partes de naturaleza distinta: una pasa **cuando alguien guarda** (aprobar) y la otra pasa **cuando pasa el tiempo** (vencer). Por eso la primera es un trigger y la segunda un job nocturno."
2. "Aprobar es que el Status **cambie** a Approved. Lo hace un field update del Approval Process, que es un update y dispara mi trigger, así que funciona venga de donde venga el cambio."
3. "El trigger no tiene lógica, delega en el handler. El handler compara `Trigger.new` contra `Trigger.oldMap` y solo actúa si el Status **cambió** a Approved."
4. "Estoy en **before update** porque modifico un campo del mismo registro: lo asigno en memoria y se guarda en el mismo save. Cero SOQL, cero DML, y la fecha la calculo una sola vez afuera del loop."
5. "De noche, el Scheduler solo lanza el Batch. El Batch trae con una query las Quotes pendientes, vencidas y no ganadas, y hace todos los recalls de la tanda con **una** llamada a `Approval.process`, con `allOrNone = false` y los errores a `Error_Log__c`."
6. "Recall es la acción `'Removed'`, la misma del botón: Salesforce pasa la Quote a Draft y la desbloquea solo. Las aprobadas no se tocan porque el recall solo existe para lo pendiente; eso lo definí con el mentor."

---

## 5. Decisiones y alternativas (resumen)

- **Parte A en before update detectando el cambio de campo:** sin DML ni recursión y sin chocar con el bloqueo de la aprobación. Se descartó after update + DML y un field update `TODAY()+30` en el Approval Process (solo cubre esa vía y es IC).
- **Parte B con Scheduler + Batch:** un trigger no se entera de que "pasó el tiempo", y el Batch da límites nuevos por cada tanda de 200. Se descartó Scheduled solo (un único juego de límites) y Queueable encadenado (encadenamiento a mano).
- **Recall con `ProcessWorkitemRequest` `'Removed'`, solo para pendientes:** no necesita `Approval.unlock`, que está desactivado en el org.

Detalle con "por qué sí / por qué no" de cada decisión, incluidas las chicas (`<= TODAY`, `IsWon`, `Set<Id>`, sin `Stateful`, 1:00): [DEV1.md §2](../code-review/DEV1.md#2-diseño-elegido).

### Por qué `Date.today()` usa la zona horaria del usuario (y por qué está bien)

- `Date.today()` devuelve **la fecha de hoy según la zona horaria del usuario que ejecuta el código** (la de su perfil: *Settings → Time Zone*). En cambio, `Datetime.now()` es un instante absoluto (internamente en UTC). Un campo **Date** como `SBQQ__ExpirationDate__c` no tiene hora ni zona: es "un día del calendario".
- **¿Quién es "el usuario" en la Parte A?** El que provoca el guardado. Cuando el aprobador hace clic en *Approve*, el field update corre como él; con `Auto_Approval`, como quien hizo el Submit. O sea, "hoy" es **el día de la aprobación tal como lo ve quien aprobó**, que es justo lo que pide el requirement ("30 days from the date in which it was approved").
- **Ejemplo:** un aprobador en Buenos Aires aprueba el 07/10 a las 22:00. En UTC ya es 08/10 a la 01:00. Si calculáramos con UTC el vencimiento quedaría un día corrido; con `Date.today()` queda 07/10 + 30 = **06/11**, que es lo que el aprobador espera.
- **En la Parte B pasa lo mismo:** `TODAY` en el WHERE del Batch ([QuoteExpirationBatch.cls:47](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L47)) se resuelve con la zona horaria del usuario que **programó el job** (frandev, America/Los_Angeles), y el cron de la 1:00 también es en su zona. Supuesto documentado en [DEV1.md §5](../code-review/DEV1.md#5-supuestos-y-decisiones) y limitación en [§10](../code-review/DEV1.md#10-limitaciones-conocidas-y-pendientes-de-qa).

### Por qué el recall es solo de aprobaciones pendientes

- En Salesforce, **"recall" solo existe mientras la aprobación está pendiente**: es retirar una solicitud que todavía nadie contestó. Técnicamente, solo hay un `ProcessInstanceWorkitem` (lo que se recallea) mientras hay una respuesta pendiente; cuando la Quote ya está Approved, ese work item **ya no existe** y no hay nada que retirar.
- Hacer algo con una Quote ya aprobada habría sido **inventar** una acción (ej. desbloquearla con `Approval.unlock` y cambiarle el Status a mano). Eso requiere el setting *Enable record locking and unlocking in Apex*, que está **desactivado** en el org, y además pisaría una decisión que un aprobador ya tomó.
- Por eso el filtro es `SBQQ__Status__c = 'In Review'` ([QuoteExpirationBatch.cls:46](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L46)). **Lo definí con el mentor (30/09/2026).**
- **¿Y para qué sirve entonces el vencimiento de una Quote aprobada?** Es la **validez de la oferta** que ve el cliente en el documento: le dice al vendedor hasta cuándo valen esos precios ([DEV1.md §7, pregunta 10](../code-review/DEV1.md#7-preguntas-probables-del-code-review)).

### Dónde aparecen los patrones base en este DEV

Explicación general de cada patrón: [00-patrones-base.md](00-patrones-base.md).

| Patrón | Dónde aparece en el DEV #1 |
|---|---|
| **Un trigger por objeto → handler** | [QuoteTrigger.trigger:13-20](../../force-app/main/default/triggers/QuoteTrigger.trigger#L13-L20) solo mira el contexto y delega. Entradas `public static` en [QuoteTriggerHandler.cls:55-75](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L55-L75); lógica `private static` desde la línea 86. El mismo trigger después sumó el after insert del DEV #3 sin mezclar lógica. |
| **`Trigger.oldMap` / detectar el cambio real** | [QuoteTriggerHandler.cls:106-109](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L106-L109): `oldQuoteByIdMap.get( newQuote.Id )` + `statusChanged && == STATUS_APPROVED`. En insert no hay `oldMap`, por eso existe un método aparte ([:86-94](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L86-L94)). |
| **Contexto correcto (before = mismo registro, sin DML)** | [QuoteTriggerHandler.cls:129](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L129): se asigna en memoria y no hay ningún `update`. |
| **Bulkificación: nada de SOQL/DML en loops** | Trigger: la fecha se calcula una vez afuera del loop ([:127](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L127)) y no hay SOQL ni DML. Batch: `Set<Id>` ([:78-81](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L78-L81)), **1** query de work items ([:87-91](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L87-L91)), **1** `Approval.process` ([:106](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L106)) y **1** insert de logs ([:116](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L116)). |
| **Condicional antes de trabajar / WHERE para reducir volumen** | `isEmpty()` + `return` en [QuoteTriggerHandler.cls:124-126](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L124-L126) y [QuoteExpirationBatch.cls:102-104](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L102-L104); los 4 filtros del WHERE en [QuoteExpirationBatch.cls:46-49](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L46-L49). |
| **Async: Scheduled delega en otra clase** | [QuoteExpirationScheduler.cls:24-26](../../force-app/main/default/classes/QuoteExpirationScheduler.cls#L24-L26): `execute` solo llama a `Database.executeBatch` (Módulo 4). |
| **Sin fallar en silencio** | `allOrNone = false` + `Error_Log__c` en [QuoteExpirationBatch.cls:106-116](../../force-app/main/default/classes/QuoteExpirationBatch.cls#L106-L116). |

---

## 6. Tests

Todos usan `@testSetup`, `Test.startTest()/stopTest()` y asserts con mensaje. En la Parte A las Quotes nacen con vencimiento **hoy + 5** para que el test no pase "de casualidad" con el default de CPQ (hoy + 30). En la Parte B las aprobaciones pendientes son **reales** (Submit con Net 60 → pendiente de Finance en `Quote_Approval_V2`).

| Tipo | Caso | Archivo:método |
|---|---|---|
| **Positivo** | Draft → Approved → hoy + 30 | [QuoteTriggerHandlerTest.cls:39](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L39) `setExpirationOnApproveTest` |
| **Positivo** | Approved → Draft → Approved: se recalcula | [QuoteTriggerHandlerTest.cls:115](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L115) `recalculatedOnReapprovalTest` |
| **Positivo** | Se crea ya aprobada → hoy + 30 | [QuoteTriggerHandlerTest.cls:139](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L139) `setExpirationOnInsertApprovedTest` |
| **Negativo** | Draft → In Review: no cambia | [QuoteTriggerHandlerTest.cls:78](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L78) `notSetOnOtherStatusTest` |
| **Negativo** | Ya aprobada, se edita otro campo: no recalcula | [QuoteTriggerHandlerTest.cls:96](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L96) `notRecalculatedWhenAlreadyApprovedTest` |
| **Negativo** | Se crea en Draft: no cambia | [QuoteTriggerHandlerTest.cls:170](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L170) `notSetOnInsertNotApprovedTest` |
| **Bulk 200** | 200 Quotes → Approved juntas | [QuoteTriggerHandlerTest.cls:56](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L56) `setExpirationOnApproveBulkTest` |
| **Bulk 200** | 200 creadas ya aprobadas | [QuoteTriggerHandlerTest.cls:153](../../force-app/main/default/classes/QuoteTriggerHandlerTest.cls#L153) `setExpirationOnInsertApprovedBulkTest` |
| **Positivo** | Vencida ayer + Opportunity abierta → Draft, 0 work items, 0 logs | [QuoteExpirationBatchTest.cls:36](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L36) `recallExpiredQuoteTest` |
| **Positivo (borde)** | Vence **hoy** → Draft | [QuoteExpirationBatchTest.cls:56](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L56) `recallQuoteExpiringTodayTest` |
| **Bulk 200** | 200 vencidas → las 200 en Draft | [QuoteExpirationBatchTest.cls:71](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L71) `recallBulkTest` |
| **Negativo** | Vence mañana → sigue In Review | [QuoteExpirationBatchTest.cls:92](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L92) `notRecalledWhenNotExpiredTest` |
| **Negativo** | Opportunity Closed Won → sigue In Review | [QuoteExpirationBatchTest.cls:109](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L109) `notRecalledWhenOpportunityWonTest` |
| **Negativo** | Ya Approved y vencida → no se toca | [QuoteExpirationBatchTest.cls:126](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L126) `notRecalledWhenAlreadyApprovedTest` |
| **Negativo** | Sin Opportunity → sigue In Review | [QuoteExpirationBatchTest.cls:145](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L145) `notRecalledWithoutOpportunityTest` |
| **Negativo** | "In Review" a mano, sin work item → sin error | [QuoteExpirationBatchTest.cls:162](../../force-app/main/default/classes/QuoteExpirationBatchTest.cls#L162) `notRecalledWithoutPendingApprovalTest` |
| **Scheduler** | Se programa con el cron y lanza el Batch (nombre de job propio de test) | [QuoteExpirationSchedulerTest.cls:14](../../force-app/main/default/classes/QuoteExpirationSchedulerTest.cls#L14) `scheduleNightlyJobTest` |

**Por qué el bulk del Batch es de 200 justo:** en un test, `execute()` corre **una sola vez**, así que 200 = una tanda completa (Módulo 4). Cobertura: 100% trigger/handler/scheduler, 93% Batch (la rama de error de un recall fallido no se puede provocar con datos de test). Ver [DEV1.md §9-10](../code-review/DEV1.md#9-build-tracker).

---

## 7. Edge cases cubiertos y supuestos

**Edge cases** (tabla completa en [DEV1.md §6](../code-review/DEV1.md#6-edge-cases)):

- Aprobación por **cualquier vía** (Approval Process, edición manual, carga de datos): se detecta el cambio del campo, no el proceso.
- Quote que **nace** aprobada (insert) → también recibe hoy + 30.
- **Re-aprobación** después de un rechazo o un recall → el vencimiento se recalcula desde la nueva aprobación.
- Editar una Quote **ya aprobada** → no se alarga el vencimiento.
- Vence **hoy** (borde) → se recallea esa misma noche (`<= TODAY`).
- Una noche en la que **el job no corrió** → la siguiente toma las atrasadas (`<=`, no `=`).
- **Opportunity ganada**, **sin Opportunity**, **ya aprobada** → no se tocan.
- **"In Review" sin work item** (Status cambiado a mano) → `return`, sin error.
- **Un recall falla** → los demás siguen y el error queda en `Error_Log__c`.
- **Recursión:** el recall pasa la Quote a Draft y dispara el trigger, pero Draft no es Approved → no hace nada.
- **Job real ya programado en el org** → el test usa `JOB_NAME + ' (Test)'`.

**Supuestos** (detalle en [DEV1.md §5](../code-review/DEV1.md#5-supuestos-y-decisiones)):

- Recall = solo aprobaciones **pendientes** (acción `'Removed'`). **Definido con el mentor.**
- "Hoy" = el día de la aprobación, en la zona horaria de quien aprueba (`Date.today()`).
- "Reaches the Expiration Date" = `SBQQ__ExpirationDate__c <= TODAY`.
- "Not Closed Won" = `Opportunity.IsWon = false` (no depende del nombre de la etapa).
- Sin Opportunity → fuera del recall.
- El job corre como el admin que lo programó (frandev): puede recallear aprobaciones enviadas por otros.

---

## 8. Cinco preguntas probables del revisor

**1. ¿Por qué before update y no after update?**
Porque cambio un campo de la misma Quote que se está guardando: en before lo asigno y se guarda solo. En after tendría que hacer otro `update`, que vuelve a disparar el trigger y choca con el bloqueo de la aprobación.

**2. Si el Approval Process es configuración, ¿por qué se entera mi trigger?**
Porque la acción del proceso es un **field update**, que por dentro es un update del registro, y todo update dispara los triggers. Por eso detecto el cambio del campo con `oldMap` y no me importa quién lo hizo.

**3. ¿Qué pasa si aprueban 200 Quotes a la vez?**
El handler recorre `Trigger.new` completo, calcula la fecha una vez afuera del loop y no hace ni SOQL ni DML: cuesta lo mismo con 1 que con 200. En el Batch, cada tanda de 200 hace 1 query, 1 `Approval.process` y 1 insert de logs. Lo prueban `setExpirationOnApproveBulkTest` y `recallBulkTest`.

**4. ¿Por qué el recall no aplica a las Quotes ya aprobadas?**
Porque recall solo existe para aprobaciones pendientes: una aprobada ya no tiene work item que retirar. Hacerlo habría requerido desbloquear por Apex (setting desactivado) y pisar la decisión de un aprobador. Lo definí con el mentor.

**5. ¿`Date.today()` no puede dar un día corrido?**
`Date.today()` usa la zona horaria del usuario que ejecuta, que en la aprobación es quien aprueba: devuelve "su" hoy, que es lo que pide el requirement. Si usara la fecha en UTC, una aprobación a la noche en Argentina quedaría con un día de más. El Batch usa la zona del admin que programó el job, y eso está documentado como limitación.

Más preguntas (14 en total): [DEV1.md §7](../code-review/DEV1.md#7-preguntas-probables-del-code-review).
