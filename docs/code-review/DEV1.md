# DEV #1 — Vencimiento automático de la Quote · Resumen para el Code Review

> **Estado:** Parte A terminada (30/09/2026). Parte B diseñada, pendiente de la decisión sobre el "recall".

## 1. Requirement

> "Whenever a Quote record is approved, the Quote Expiration Date should be set to 30 days from the date in which it was approved. If a Quote reaches the Quote Expiration Date and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be recalled."

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "whenever a Quote record is approved" | `SBQQ__Status__c` **pasa a** `Approved` (o la Quote nace aprobada) | `QuoteTriggerHandler.beforeUpdate` / `beforeInsert` |
| (B) "30 days from the date in which it was approved" | `SBQQ__ExpirationDate__c = hoy + 30`, pisando el default de CPQ | `setExpirationDate` |
| (C) "reaches the Quote Expiration Date ... not Closed Won" | Chequeo diario de Quotes vencidas | **Parte B** (Batch + Scheduler) — pendiente |
| (D) "approvals should be recalled" | A definir (ver sección 8) | **Parte B** — pendiente |

---

## 2. Componentes (Parte A)

| Componente | Tipo | Rol |
|---|---|---|
| `QuoteTrigger` | Apex Trigger | Único trigger propio de `SBQQ__Quote__c`, sin lógica. `before insert` y `before update`. |
| `QuoteTriggerHandler` | Apex Class | Métodos de entrada por contexto + lógica `private static`. |
| `TestDataFactory.buildQuotes` | Test utility | Arma Quotes con Status y vencimiento indicados. |
| `QuoteTriggerHandlerTest` | Test Class | 8 tests. |

En el org también existen `SBQQ.QuoteBefore` y `SBQQ.QuoteAfter`, del paquete CPQ. No son nuestros y no se pueden modificar.

---

## 3. Cómo se aprueba una Quote en el org

Los 3 Approval Processes (`Discount_Approval`, `Billing_Approval`, `Auto_Approval`) tienen las mismas acciones:

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

## 8. Parte B — Diseño (pendiente de construir)

**Qué hace:** todos los días busca Quotes aprobadas que ya vencieron y cuya Opportunity no está Closed Won, y les hace el "recall".

- `QuoteExpirationScheduler` (`Schedulable`): su `execute()` solo llama a `Database.executeBatch( new QuoteExpirationBatch() )`. Regla del curso: no poner lógica en el Scheduled.
- `QuoteExpirationBatch` (`Database.Batchable<SObject>`):
  - `start`: `SBQQ__Status__c = 'Approved'` AND `SBQQ__ExpirationDate__c <= TODAY` AND `SBQQ__Opportunity2__r.IsWon = false`.
  - `execute`: el "recall" (a definir) con `Database.update( lista, false )` + `ErrorLogUtil`.
  - `finish`: vacío.
- **Por qué Batch y no solo Scheduled:** cada chunk de 200 tiene sus propios límites, así que escala sin depender del volumen.
- **Supuesto:** las Quotes sin Opportunity quedan afuera. Con `SBQQ__Opportunity2__c` en null, `IsWon = false` no matchea en SOQL.
- **Abierto: qué es el "recall".** Una aprobación terminada no se puede recallear con la API (solo las pendientes). La opción "desbloquear + volver a Draft" necesita *Enable record locking and unlocking in Apex*, que hoy está desactivado. Se decide con el mentor.

---

## 9. Prueba en el org (30/09/2026)

Opportunity "IC Test - Auto Approval" → **Q-00061** creada con Net 30, sin descuento y vencimiento forzado a 05/10/2026 → Submit → `Auto_Approval` la aprueba en el momento → **Status Approved, vencimiento 30/10/2026** (hoy + 30). Se volvió a consultar después del commit y la fecha seguía igual. El `SBQQ.QuoteBefore` de CPQ no la pisa. Sin Error Logs.

**Cómo se prueba en la UI (demo):**
1. Abrir una Quote en Draft (Net 30, sin descuento) y anotar su Expiration Date.
2. **Submit for Approval**. Con `Auto_Approval` se aprueba sola; con los otros procesos, aprobarla desde el approver.
3. Refrescar: Status **Approved** y Expiration Date = **hoy + 30**.

---

## 10. Tests y Build Tracker

**8/8 tests pasan. Cobertura del 100%.** Los 11 tests de `OrderTriggerHandlerTest` siguen pasando después del cambio en `TestDataFactory`.

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| QuoteTrigger | QuoteTriggerHandlerTest | 30/09/2026 | 100% |
| QuoteTriggerHandler | QuoteTriggerHandlerTest | 30/09/2026 | 100% |
