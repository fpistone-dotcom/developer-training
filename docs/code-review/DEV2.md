# DEV #2 — Activación automática de la Order · Resumen para el Code Review

## 1. Requirement

> "As part of the Provisioning Team, I want the ability to automatically activate an Order record whenever it is created and the Price Calculation Status on the Order is updated to either 'Completed' or 'Not Needed'."

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "automatically activate an Order" | Poner `Status = 'Activated'` sin intervención humana | `OrderTriggerHandler` y `OrderActivationQueueable` |
| (B) "whenever it is created" | La Order se crea ya lista | `afterInsert` → `OrderActivationQueueable` |
| (C) "Price Calculation Status ... is updated" | El campo **cambia** a un valor listo | `beforeUpdate`, comparando con `Trigger.oldMap` |
| (D) "'Completed' or 'Not Needed'" | Solo esos dos valores | Constante `READY_PRICE_CALC_STATUSES` |

**Interpretación:** se cubren los dos momentos. Una Order que **se crea** con un valor listo y una Order que ya existe y **pasa a** un valor listo.

**Valor para el negocio:** completa la cadena del Req #31, que ahora es 100% automática:
`Closed Won` → (Flow 1) Quote Ordered → CPQ crea la Order → **(DEV #2) Order Activated** → (Flow 2) Order Contracted → CPQ crea Contract + Subscription.

---

## 2. Componentes

| Componente | Tipo | Rol |
|---|---|---|
| `OrderTrigger` | Apex Trigger | Único trigger de Order, sin lógica. `before update` y `after insert`. |
| `OrderTriggerHandler` | Apex Class | Métodos de entrada por contexto + lógica `private static`. |
| `OrderActivationQueueable` | Apex Class (Queueable) | Activación diferida para Orders que nacen listas. |
| `ErrorLogUtil` | Apex Class | Arma logs en memoria (`buildLog`) y los guarda con un solo insert (`saveLogs`). |
| `Error_Log__c` | Custom Object | Class Name, Record Id y Error Message. Con tab, layout y list view. |
| `Error_Log_Access` | Permission Set | Lectura de `Error_Log__c`. |
| `TestDataFactory` | Test utility | Datos de prueba compartidos (DRY). |
| `OrderTriggerHandlerTest`, `ErrorLogUtilTest` | Test Classes | 14 tests. |

---

## 3. El problema central

Salesforce **no permite activar una Order sin Order Products**, y CPQ inserta **primero la Order y después sus productos**, dentro de la misma transacción. Activar en el momento del insert fallaría y cancelaría la creación completa de la Order.

Por eso hay dos caminos:

| Camino | Cuándo | Contexto | Cómo activa |
|---|---|---|---|
| **Update** (camino principal con CPQ) | El status **pasa a** Completed/Not Needed | `before update` | Asigna `Status` en memoria, sin DML |
| **Insert** | La Order **nace** con Completed/Not Needed | `after insert` + Queueable | El Queueable corre después del commit, cuando los productos ya existen |

---

## 4. Evidencia de la prueba end-to-end (debug log, 29/09/2026)

Opportunity "DEV2 E2E Test - Order Activation" → Q-00057 (Monthly Named Users) → **Order 00000120** → **Contract 00000108** + **SUB-0000011**. Sin errores de queueable y con Error Logs vacío.

| Transacción | Hora (UTC) | PriceCalcStatus | Qué hizo nuestro código |
|---|---|---|---|
| T1: Closed Won | 19:34:24 | Order insertada con `Not Started` | `afterInsert`: no está lista → no encola nada |
| T1 | 19:34:24 | Productos insertados. CPQ hace un update (`Not Started` → `Not Started`) | `beforeUpdate`: no cambió → no hace nada |
| T1 | — | CPQ la pasa a `Queued` y encola su calculador | — |
| T2: `OrderPriceCalculatorService` (CPQ) | 19:34:26 | `Queued` → **`Not Needed`** | `beforeUpdate`: cambió, está lista y tiene productos → **Activated** |
| T2 | 19:34:27 | — | Flow 2 → Contracted → CPQ encola `QueueableContractOrdersClient` |
| T3: contracting (CPQ) | 19:34:32 | — | Contract + Subscription creados |

**Supuesto corregido:** partimos de que la Order de CPQ nacía con `Not Needed`. El debug log mostró que nace con `Not Started` y que el calculador de CPQ la pasa a `Not Needed` después. En el flujo estándar, **la activación la hace el `before update`**.

**Por qué esto valida el diseño:** en T2 estamos dentro del Queueable de CPQ, donde solo se puede encolar **un** job más, y CPQ lo usa para el contracting. Si el camino del update hubiera usado un Queueable, habría dado "Too many queueable jobs" y la cadena se rompía.

**Por qué se mantiene el Queueable:** el requirement pide cubrir *"whenever it is created"*. Una Order puede nacer lista por otras vías (carga manual, Data Loader, integraciones, otra configuración de CPQ). El camino está cubierto por tests unitarios. **La prueba en vivo en el org queda pendiente para QA** (ver [`docs/qa-pending.md`](../qa-pending.md), caso QA-DEV2-01).

---

## 5. Decisiones de diseño

1. **Apex y no Flow.** Es un requirement DEV, y el control del orden de eventos, de los límites y de los errores es más preciso en Apex.
2. **Un trigger por objeto, sin lógica.** El orden de ejecución es predecible, y los métodos de entrada (`beforeUpdate`, `afterInsert`) solo delegan en métodos `private static`.
3. **`before update` para el camino del update.** Modifica el mismo registro, sin DML ni recursión. No encola jobs dentro del Queueable de CPQ.
4. **`after insert` + Queueable para el camino del insert.** En before insert no hay Id. El Queueable se libera recién cuando la transacción hace commit, así que los productos ya existen.
5. **Queueable y no `@future`.** Un Future no se puede llamar desde otro Future ni desde un Batch, y el Queueable devuelve un Id de job que se puede monitorear.
6. **Detectar el cambio real con `Trigger.oldMap`.** "Is updated to" significa "pasa a". Si el campo no cambió, la Order no se reprocesa, y sin candidatas no se ejecuta la query.
7. **Verificar productos antes de activar.** `SELECT Id, (SELECT Id FROM OrderItems LIMIT 1) FROM Order WHERE Id IN :ids`: una sola query y como máximo una fila hija por Order.
8. **El Queueable vuelve a consultar antes de activar**, para trabajar con datos frescos (la Order pudo cambiar mientras esperaba).
9. **`Database.update( lista, false )`.** Si una Order falla, las demás se activan igual. Los errores se recorren por posición porque un `SaveResult` fallido no trae Id.
10. **`Error_Log__c` + `ErrorLogUtil`.** Los errores quedan guardados y visibles, no solo en un debug. Los logs se arman en el loop y se guardan con **un solo insert**.
11. **Logs en `AccessLevel.SYSTEM_MODE`.** Son registros del sistema: se guardan aunque el usuario que disparó el proceso no tenga permisos. Quién puede **verlos** lo sigue controlando el permission set.
12. **Chequeo de `Limits` antes de encolar.** Pasarse del límite tira una excepción que no se puede atrapar y cancela la creación de la Order. En ese caso se registra un Error Log y la Order se crea igual.
13. **DRY.** La regla está en `isReadyToActivate` y las constantes (`STATUS_DRAFT`, `STATUS_ACTIVATED`, `READY_PRICE_CALC_STATUSES`) se reutilizan en el Queueable.
14. **`with sharing`.** Quien edita una Order ya puede ver sus productos, así que no hace falta saltear la seguridad.

---

## 6. Supuestos

- Solo se activan Orders en `Draft`. El picklist `Status` del org solo tiene `Draft` y `Activated`, y `== 'Draft'` evita activar estados futuros como "Cancelled".
- Los valores listos son exactamente `Completed` y `Not Needed` (valores del picklist `SBQQ__PriceCalcStatus__c`: Not Started, Not Needed, Queued, Aborted, Failed, Completed).

---

## 7. Edge cases cubiertos (todos con test)

| Caso | Resultado esperado | Test |
|---|---|---|
| Order creada con `Not Needed` + productos | Activated (vía Queueable) | `activateOnInsertTest` |
| 200 Orders creadas juntas | 200 Activated, 1 solo Queueable | `activateOnInsertBulkTest` |
| Order creada con `Queued` | Draft | `notActivatedOnInsertWhenNotReadyTest` |
| Order creada lista sin productos | Draft, sin error | `notActivatedOnInsertWithoutItemsTest` |
| Cupo de Queueables lleno | La Order se crea igual + 1 Error Log | `logErrorWhenQueueableLimitReachedTest` |
| Salesforce rechaza la activación | Draft + 1 Error Log | `logErrorWhenActivationFailsTest` |
| `Queued` → `Completed` con productos | Activated en el momento | `activateOnUpdateTest` |
| 200 Orders pasan a `Completed` juntas | 200 Activated | `activateOnUpdateBulkTest` |
| `Queued` → `Failed` | Draft | `notActivatedOnUpdateToNotReadyValueTest` |
| → `Completed` sin productos | Draft, sin error | `notActivatedOnUpdateWithoutItemsTest` |
| Se edita otro campo y el status no cambia | No se reprocesa | `notActivatedWhenPriceCalcStatusDidNotChangeTest` |
| `saveLogs` con datos / con lista vacía | Guarda / no hace nada | `saveLogsTest`, `saveLogsEmptyListTest` |

---

## 8. Bulkificación y límites

| Contexto (200 Orders) | SOQL | DML | Jobs |
|---|---|---|---|
| before update | 1 (solo si alguna califica) | 0 | 0 |
| after insert | 0 | 0 (1 si hay que registrar el error de límite) | 1 |
| Queueable | 1 | 1 update (+1 insert de logs si hubo errores) | 0 |

La cantidad es la misma para 1 o 200 registros. No hay SOQL ni DML dentro de loops.

**Recursión:** el update del Queueable vuelve a disparar `before update`, pero el PriceCalcStatus no cambió, así que el filtro devuelve vacío. No hace falta una variable estática.

---

## 9. Limitaciones conocidas

1. **Validation rule que bloquee la activación.** En el camino del update, activamos dentro del guardado de CPQ: una regla que impida activar haría fallar ese guardado. Hoy no existe ninguna.
2. **Order lista antes de tener productos.** Si una Order llega a un status listo **antes** de tener productos, no se activa sola y hay que activarla a mano. Es posible en cargas manuales o integraciones, no en el flujo de CPQ, según el debug log. No se resolvió con un trigger en OrderItem porque activaría la Order con la primera tanda de productos y haría fallar las siguientes (Salesforce no deja agregar productos a una Order activada).
3. **Demora en el camino del insert.** El Queueable corre unos segundos después. Es aceptable, porque el contracting de CPQ también es async.

---

## 10. Tests y Build Tracker

**14/14 tests pasan. Cobertura del 100%.**

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| OrderTrigger | OrderTriggerHandlerTest | 29/09/2026 | 100% |
| OrderTriggerHandler | OrderTriggerHandlerTest | 29/09/2026 | 100% |
| OrderActivationQueueable | OrderTriggerHandlerTest | 29/09/2026 | 100% |
| ErrorLogUtil | ErrorLogUtilTest | 29/09/2026 | 100% |

---

## 11. Cómo se prueba en la UI (demo)

1. Crear una Opportunity en *Burlington Textiles Corp of America*.
2. Crear una Quote **Primary** con **Monthly Named Users** (producto de suscripción) y esperar unos segundos a que CPQ calcule.
3. **Submit for Approval** y aprobarla (Status = Approved).
4. Pasar la Opportunity a **Closed Won**.
5. Esperar unos 10 segundos y abrir la Order:
   - Status **Activated**
   - **Contracted** marcado
   - En la Account, un **Contract** con su **Subscription**
6. La tab **Error Logs** tiene que estar vacía.

**Pendiente para QA:** la prueba en vivo del camino del insert (Order que nace con `Not Needed`). Ver [`docs/qa-pending.md`](../qa-pending.md).
