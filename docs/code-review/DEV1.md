# DEV #1 — Vencimiento automático de la Quote · Resumen para el Code Review

> **Estado:** Parte A y Parte B terminadas, deployadas y probadas en el org (30/09/2026). Job nocturno programado.

## 1. Requirement

> "Whenever a Quote record is approved, the Quote Expiration Date should be set to 30 days from the date in which it was approved. If a Quote reaches the Quote Expiration Date and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be recalled."

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "whenever a Quote record is approved" | `SBQQ__Status__c` **pasa a** `Approved` (o la Quote nace aprobada) | `QuoteTriggerHandler.beforeUpdate` / `beforeInsert` |
| (B) "30 days from the date in which it was approved" | `SBQQ__ExpirationDate__c = hoy + 30`, pisando el default de CPQ | `setExpirationDate` |
| (C) "reaches the Quote Expiration Date" | `SBQQ__ExpirationDate__c <= TODAY`, chequeado todas las noches | `QuoteExpirationBatch.start` + `QuoteExpirationScheduler` |
| (D) "the related Opportunity is still not 'Closed Won'" | Con Opportunity y `IsWon = false` | `QuoteExpirationBatch.start` |
| (E) "the Quote approvals should be recalled" | Retirar la aprobación **pendiente** (botón "Recall" = acción `'Removed'`) | `QuoteExpirationBatch.recallPendingApprovals` |

---

## 2. Componentes

| Componente | Tipo | Parte | Rol |
|---|---|---|---|
| `QuoteTrigger` | Apex Trigger | A | Único trigger propio de `SBQQ__Quote__c`, sin lógica. `before insert` y `before update`. |
| `QuoteTriggerHandler` | Apex Class | A | Métodos de entrada por contexto + lógica `private static`. |
| `QuoteExpirationScheduler` | Apex Class (Schedulable) | B | "Despertador" nocturno: solo lanza el Batch. |
| `QuoteExpirationBatch` | Apex Class (Batchable) | B | Busca las Quotes vencidas con aprobación pendiente y les hace recall. |
| `TestDataFactory.buildQuotes`, `createOpportunity` | Test utility | A y B | Datos de prueba compartidos. |
| `QuoteTriggerHandlerTest` | Test Class | A | 8 tests. |
| `QuoteExpirationBatchTest` | Test Class | B | 8 tests, con aprobaciones pendientes reales. |
| `QuoteExpirationSchedulerTest` | Test Class | B | 1 test. |

En el org también existen `SBQQ.QuoteBefore` y `SBQQ.QuoteAfter`, del paquete CPQ. No son nuestros y no se pueden modificar.

---

## 3. Cómo se aprueba una Quote en el org

Los 2 Approval Processes activos (`Auto_Approval` y `Quote_Approval_V2`, con criterios de entrada opuestos) tienen las mismas acciones:

| Momento | Field update | Status |
|---|---|---|
| Submit | `Set_Quote_Status_In_Review` | In Review |
| Aprobación final | `Set_Quote_Status_Approved` (+ template Final, bloquea) | **Approved** |
| Rechazo | `Set_Quote_Status_Denied` | Denied |
| Recall (solo pendientes) | `Set_Quote_Status_Draft` | Draft |

**Consecuencia para el diseño:** "aprobada" = el campo `SBQQ__Status__c` pasa a `Approved`. Un field update de un Approval Process **dispara los triggers de update**, así que el trigger ve la aprobación igual que si la hiciera un usuario. Detectamos el **cambio del campo**, no el proceso: funciona por cualquier vía.

---

## 4. Decisiones de diseño

1. **`before` y no `after`.** Modificamos un campo del **mismo registro**: en before se asigna en memoria y Salesforce lo guarda solo. **0 DML y 0 SOQL.** En after habría que hacer un `update` extra, que vuelve a disparar el trigger (recursión) y además choca con el record lock que pone la aprobación.
2. **Detectar el cambio con `Trigger.oldMap`.** "Is approved" = el Status **pasa a** Approved. Si la Quote ya estaba aprobada y se edita otro campo, la fecha de aprobación no cambió, así que no se recalcula.
3. **También `before insert`.** Una Quote puede nacer aprobada (carga de datos, clone, tests). No tiene valor anterior: alcanza con `Status == Approved`. Cuesta cero SOQL.
4. **Apex y no un field update del Approval Process.** Un field update `TODAY() + 30` solo cubriría las aprobaciones por proceso. Además es un requirement DEV y no tocamos el IC.
5. **La fecha se calcula una sola vez** (`Date.today().addDays(30)`), afuera del loop.
6. **DRY.** La regla está en `setExpirationDate`, y las constantes `STATUS_APPROVED` y `DAYS_UNTIL_EXPIRATION` son `public` para reutilizarlas en la Parte B y en los tests.
7. **Sin recursión.** Before no hace DML. Cuando la Parte B vuelva la Quote a otro status, el trigger no reacciona (solo reacciona al pasar **a** Approved).
8. **Sin `ErrorLogUtil` en la Parte A.** No hay DML ni nada que pueda fallar parcialmente: solo una asignación en memoria. Se va a usar en la Parte B.

---

## 5. Supuestos

- "Hoy" es el día de la aprobación, porque el trigger corre **en la misma transacción** que aprueba la Quote. `Date.today()` usa la zona horaria del usuario que ejecuta la transacción.
- Si el usuario cambia el vencimiento **en el mismo guardado** en que aprueba, gana el nuestro (lo pide el requirement).
- Si una Quote vuelve a Draft y se aprueba de nuevo, el vencimiento se recalcula desde la nueva aprobación.

---

## 6. Edge cases cubiertos (todos con test)

Todas las Quotes de test nacen con vencimiento **hoy + 5**. El default de CPQ (creación + 30) coincide con hoy + 30, y un test que solo mirara la fecha final pasaría aunque el trigger no hiciera nada.

| Caso | Resultado esperado | Test |
|---|---|---|
| Draft → Approved | hoy + 30 | `setExpirationOnApproveTest` |
| 200 Quotes → Approved juntas | Las 200 con hoy + 30 | `setExpirationOnApproveBulkTest` |
| Draft → In Review | Sin cambios | `notSetOnOtherStatusTest` |
| Ya aprobada, se edita otro campo | Sin recálculo | `notRecalculatedWhenAlreadyApprovedTest` |
| Approved → Draft → Approved | Se recalcula | `recalculatedOnReapprovalTest` |
| Se crea ya aprobada | hoy + 30 | `setExpirationOnInsertApprovedTest` |
| 200 creadas aprobadas | Las 200 con hoy + 30 | `setExpirationOnInsertApprovedBulkTest` |
| Se crea en Draft | Sin cambios | `notSetOnInsertNotApprovedTest` |

En un test no se puede correr el Approval Process real: se cambia el Status con DML, que es exactamente lo que hace su field update. La aprobación real se probó en el org (sección 9).

---

## 7. Bulkificación y límites

| Contexto (200 Quotes) | SOQL | DML |
|---|---|---|
| before insert | 0 | 0 |
| before update | 0 | 0 |

Es el mismo costo para 1 o para 200 registros.

---

## 8. Parte B — Recall de aprobaciones vencidas

### 8.1 Qué significa "recall" (definido con el mentor)

Retirar una aprobación **pendiente**, igual que el botón **"Recall"** de la UI. Las Quotes ya aprobadas **no se tocan** (supuesto documentado): una aprobación terminada no tiene nada que retirar, y "desbloquear + volver a Draft" necesitaría *Enable record locking and unlocking in Apex*, que está desactivado.

En Apex, las acciones sobre una aprobación pendiente se hacen con `Approval.ProcessWorkitemRequest` (Approve, Reject o **Removed**). **`'Removed'` es el Recall**: Salesforce ejecuta la Recall Action del proceso (`Set_Quote_Status_Draft`) y desbloquea la Quote. No hace falta `Approval.unlock`.

**Qué resuelve en la práctica:** una Quote In Review tiene todavía el vencimiento por defecto de CPQ (creación + 30), porque el nuestro se pone recién al aprobar. Si vence sin que nadie la apruebe ni gane la Opportunity, la aprobación queda colgada en "Items to Approve". El recall la retira y la Quote vuelve a Draft, editable, para que el vendedor la actualice y la reenvíe.

### 8.2 Por qué Batch + Scheduler y no un trigger

Un trigger corre solo cuando **alguien guarda** un registro. "La Quote venció" no es un guardado: es el calendario que avanza. Hace falta algo que corra **por tiempo**.

- **`QuoteExpirationScheduler` (Schedulable):** el "despertador". Corre todas las noches a la 1:00 (`'0 0 1 * * ?'`) y solo lanza el Batch. La regla del curso es no poner lógica en el Scheduled.
- **`QuoteExpirationBatch` (Batchable):** hace el trabajo en tandas de 200 registros, **cada una con sus propios governor limits**, así que escala con cualquier volumen. Si todo corriera en el Scheduler, sería una sola transacción con un solo juego de límites.

### 8.3 Cómo funciona

1. **`start`:** `SBQQ__Status__c = 'In Review'` AND `SBQQ__ExpirationDate__c <= TODAY` AND `SBQQ__Opportunity2__c != null` AND `SBQQ__Opportunity2__r.IsWon = false`. Devuelve un `QueryLocator`.
2. **`execute`** (por tanda) → `recallPendingApprovals`:
   - **Una** query a `ProcessInstanceWorkitem` con los Ids de la tanda, afuera de cualquier loop.
   - Un request `'Removed'` por work item, con un comentario que queda en el Approval History.
   - Una lista paralela con la Quote de cada request.
   - **Un** `Approval.process( lista, false )`: con `allOrNone = false`, si un recall falla los demás se hacen igual.
   - Los resultados se recorren **por posición** (un resultado fallido no trae el Id). Los errores van a `ErrorLogUtil` con **un solo insert**.
3. **`finish`:** vacío (la interfaz lo exige).
4. **Cadena automática:** recall → Recall Action (Draft) → `QuoteTrigger`. El Status no pasa a Approved, así que no hace nada y no hay recursión.

### 8.4 Decisiones y supuestos

- **"Reaches the Expiration Date" = `<= TODAY`:** el recall se hace el mismo día del vencimiento (a la 1:00).
- **Quotes sin Opportunity:** quedan afuera (supuesto documentado).
- **Quotes "In Review" sin aprobación pendiente** (Status cambiado a mano): el Batch las encuentra pero no hay work item, así que no las toca y no genera errores.
- **El job corre como el usuario que lo programó** (admin). Retirar aprobaciones enviadas por otros requiere ser admin o el que la envió.
- **`with sharing`:** como el job corre como admin, ve todas las Quotes.
- **Genérico `<SObject>`:** lo exige la interfaz `Database.Batchable`. No es una elección de diseño.
- **`Database.Stateful` no se usa:** los errores se guardan en cada tanda, así que no hace falta mantener estado entre tandas.

### 8.5 Bulkificación y límites

| Contexto (una tanda de 200) | SOQL | DML / Approval |
|---|---|---|
| start | 1 (QueryLocator) | 0 |
| execute | 1 (work items) | 1 `Approval.process` (+1 insert de logs si hubo errores) |

### 8.6 Edge cases cubiertos (todos con test)

Las aprobaciones pendientes de los tests son **reales**: se hace Submit con `Approval.process` y `Quote_Approval_V2` corre en el test (Net 60 → pendiente de Finance).

| Caso | Resultado esperado | Test |
|---|---|---|
| Vencida ayer + Opportunity abierta | Draft, sin work item, sin Error Logs | `recallExpiredQuoteTest` |
| Vence **hoy** (borde) | Draft | `recallQuoteExpiringTodayTest` |
| 200 vencidas | Las 200 en Draft | `recallBulkTest` |
| Vence mañana | In Review, sigue pendiente | `notRecalledWhenNotExpiredTest` |
| Opportunity Closed Won | In Review | `notRecalledWhenOpportunityWonTest` |
| Ya Approved y vencida | Approved (no se toca) | `notRecalledWhenAlreadyApprovedTest` |
| Sin Opportunity | In Review | `notRecalledWithoutOpportunityTest` |
| "In Review" sin aprobación pendiente | In Review, sin error | `notRecalledWithoutPendingApprovalTest` |
| El Scheduler se programa y lanza el Batch | `CronTrigger` con el cron + 1 `AsyncApexJob` | `scheduleNightlyJobTest` |

### 8.7 Limitación conocida

Las 2 líneas que arman el Error Log cuando un recall **falla** (`QuoteExpirationBatch`, líneas 112-113) no están cubiertas: un recall real no se puede hacer fallar con datos normales de test. Cobertura de la clase: 93%.

---

## 9. Pruebas en el org (30/09/2026)

**Parte A:** Opportunity "IC Test - Auto Approval" → **Q-00061** creada con Net 30, sin descuento y vencimiento forzado a 05/10/2026 → Submit → `Auto_Approval` la aprueba en el momento → **Status Approved, vencimiento 30/10/2026** (hoy + 30). Se volvió a consultar después del commit y la fecha seguía igual. El `SBQQ.QuoteBefore` de CPQ no la pisa. Sin Error Logs.

**Parte B:** **Q-00079** (Net 60, vencimiento 29/09, misma Opportunity abierta) → Submit → In Review → `Database.executeBatch( new QuoteExpirationBatch() )` → job `Completed`, 0 errores → **Q-00079 en Draft**, con el paso "Removed" y el comentario automático en el Approval History. Q-00060 (In Review, vence el 30/10) no se tocó. Sin Error Logs.

**Job programado:** "Quote Expiration Recall - Nightly", `0 0 1 * * ?`, estado WAITING, primer disparo 01/10/2026 1:00 (America/Los_Angeles).

### Cómo se prueba en la UI (demo)

**Parte A — vencimiento al aprobar:**
1. Abrir una Quote en Draft (Net 30, sin descuento) y anotar su Expiration Date.
2. **Submit for Approval**. Con `Auto_Approval` se aprueba sola; con `Quote_Approval_V2`, aprobarla desde el approver.
3. Refrescar: Status **Approved** y Expiration Date = **hoy + 30**.

**Parte B — recall de una Quote vencida:**
1. Crear una Quote en una Opportunity abierta con **Payment Terms = Net 60** y editar **Expiration Date = ayer**.
2. **Submit for Approval** → Status **In Review**, con el candado y la aprobación en "Items to Approve" del approver de Finance.
3. Abrir la **Developer Console → Debug → Open Execute Anonymous Window** y ejecutar:
   ```apex
   Database.executeBatch( new QuoteExpirationBatch() );
   ```
   Es lo mismo que hace el job a la 1:00, sin esperar.
4. Esperar unos segundos (se puede ver el job en **Setup → Apex Jobs**) y refrescar la Quote: Status **Draft**, sin candado, y en **Approval History** el paso **Recalled** con el comentario *"Recalled automatically: ..."*. La aprobación desaparece de "Items to Approve".
5. Mostrar el job programado en **Setup → Scheduled Jobs** ("Quote Expiration Recall - Nightly").

---

## 10. Tests y Build Tracker

**Todos los tests locales pasan: 30/30** (Order 11, ErrorLogUtil 2, Parte A 8, Parte B 9). **Cobertura del org: 98%.**

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| QuoteTrigger | QuoteTriggerHandlerTest | 30/09/2026 | 100% |
| QuoteTriggerHandler | QuoteTriggerHandlerTest | 30/09/2026 | 100% |
| QuoteExpirationBatch | QuoteExpirationBatchTest | 30/09/2026 | 93% |
| QuoteExpirationScheduler | QuoteExpirationSchedulerTest | 30/09/2026 | 100% |
