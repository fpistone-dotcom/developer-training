# DEV #2 · Paso a paso para la defensa (activación automática de la Order)

> **Para qué sirve este documento:** es la guía para **mostrar y explicar** el DEV #2 en el Code Review, en el orden en que se ejecuta. El detalle completo (diseño, bloques, edge cases, 10 preguntas, Build Tracker) está en [`docs/code-review/DEV2.md`](../code-review/DEV2.md); acá no se repite, se referencia. Los patrones que se repiten en todos los DEV están en [`00-patrones-base.md`](00-patrones-base.md). De hecho, el DEV #2 es el **ejemplo principal** de esa guía (secciones 3 y 4).
>
> Los números de línea son del commit `18d2af9` (07/10/2026). Si el código cambia, revisarlos.

---

## 1. Requirement en 2 líneas (palabras de vendedor)

- "Cuando gano la venta y CPQ me arma la Order, no quiero tener que entrar a activarla a mano: apenas CPQ termina de calcular los precios, la Order se tiene que activar sola."
- "Y como la Order activada es lo que dispara el Contract, eso me deja el Contract y las Subscriptions listas sin tocar nada."

Texto original y tabla de partes (A)…(D): [DEV2.md §1](../code-review/DEV2.md#1-qué-pide-el-requirement).

---

## 2. Flujo lógico (sin código)

1. "Lista para activar" = la Order está en **Draft** y su `SBQQ__PriceCalcStatus__c` es **Completed** o **Not Needed** (CPQ terminó, o no tenía nada que calcular).
2. **El problema de CPQ:** CPQ inserta **primero la Order** y **después sus Order Products**, en la misma transacción. Y Salesforce **no deja activar una Order sin productos**: si la activo en el momento del insert, da error y se cancela la creación entera de la Order.
3. Por eso hay **dos caminos**, según *cuándo* la Order queda lista:
   - Si **nace** lista (insert): todavía no tiene productos → no la activo ahí; **anoto** la activación en un **Queueable**, que corre después del commit, cuando los productos ya existen.
   - Si **pasa a** estar lista (update): los productos ya existen → la activo en **before update**, cambiando el campo en memoria, sin DML.
4. **En el flujo real de CPQ gana el camino del update:** la Order nace con `Not Started`, CPQ la pasa a `Queued` y unos segundos después su calculador la pasa a `Not Needed`. Ese update es el que la activa (verificado con debug log). El camino del Queueable cubre las Orders que nacen listas (Data Loader, integraciones), porque el requirement dice *"whenever it is created"*.
5. Solo actúo si el status **cambió** a un valor listo (nuevo vs viejo). Editar otro campo no reprocesa la Order.
6. Una vez Activated, el **Flow 2 del IC** la marca Contracted y CPQ crea Contract + Subscriptions + Assets.

---

## 3. Cronología demo → código

### La cadena completa del Req #31 (IC + DEV #2)

```
Opportunity → Closed Won
   └─ Flow 1  Auto_Create_Order_On_Closed_Won     (IC, after save en Opportunity)
        └─ Quote: SBQQ__Ordered__c = true
             └─ CPQ crea la Order (Draft, Not Started) y DESPUÉS sus Order Products
                  └─ CPQ: Not Started → Queued → (Queueable de CPQ) → Not Needed
                       └─ DEV #2  OrderTrigger before update → Status = Activated
                            └─ Flow 2  Auto_Contract_Order_On_Activation   (IC, after save en Order)
                                 └─ Order: SBQQ__Contracted__c = true
                                      └─ CPQ (async) crea Contract + Subscriptions + Assets
```

### Camino real (el de la demo): Opportunity Closed Won

Son **3 transacciones** separadas (T1, T2, T3). Horarios reales del debug log del 29/09/2026 en [DEV2.md §8](../code-review/DEV2.md#8-cómo-se-prueba-en-la-demo).

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Tengo una Opportunity con su Quote **Primary** en **Approved** (producto de suscripción, ej. *Monthly Named Users*). Paso la Opportunity a **Closed Won**. | Update de la Opportunity → **Flow 1** (IC). | [Auto_Create_Order_On_Closed_Won.flow-meta.xml:85-96](../../force-app/main/default/flows/Auto_Create_Order_On_Closed_Won.flow-meta.xml#L85-L96) | Criterio de entrada: `StageName` **pasa a** Closed Won (`doesRequireRecordChangedToMeetCriteria = true`). Busca la Quote Primary aprobada y no ordenada. | **T1** · Flow after save |
| 2 | (no se ve) | Flow 1 actualiza la Quote. | [Auto_Create_Order_On_Closed_Won.flow-meta.xml:72-74](../../force-app/main/default/flows/Auto_Create_Order_On_Closed_Won.flow-meta.xml#L72-L74) | `SBQQ__Ordered__c = true`. Esto hace que **CPQ** cree la Order. | T1 · Flow |
| 3 | (no se ve) | CPQ **inserta la Order** (Draft, `PriceCalcStatus = Not Started`) → `OrderTrigger`. | [OrderTrigger.trigger:12-13](../../force-app/main/default/triggers/OrderTrigger.trigger#L12-L13) | `isAfter && isInsert` → `OrderTriggerHandler.afterInsert( Trigger.new )`. | T1 · **after insert** |
| 4 | (no se ve) | → handler | [OrderTriggerHandler.cls:52-54](../../force-app/main/default/classes/OrderTriggerHandler.cls#L52-L54), [:96-104](../../force-app/main/default/classes/OrderTriggerHandler.cls#L96-L104) | `enqueueActivationForNewOrders` pregunta `isReadyToActivate`: `Not Started` **no** es listo → el Set queda vacío → `return`. **No encola nada.** | T1 · after insert |
| 5 | (no se ve) | CPQ **inserta los Order Products** y actualiza la Order (`Not Started` → `Not Started`) → `OrderTrigger`. | [OrderTrigger.trigger:10-11](../../force-app/main/default/triggers/OrderTrigger.trigger#L10-L11) | `isBefore && isUpdate` → `beforeUpdate( Trigger.new, Trigger.oldMap )`. | T1 · **before update** |
| 6 | (no se ve) | → filtro | [OrderTriggerHandler.cls:143-153](../../force-app/main/default/classes/OrderTriggerHandler.cls#L143-L153) | `filterOrdersReadyOnUpdate`: el valor **no cambió** → lista vacía → [:69-71](../../force-app/main/default/classes/OrderTriggerHandler.cls#L69-L71) `return` **antes de la SOQL**. | T1 · before update |
| 7 | (no se ve) | CPQ pasa la Order a **`Queued`** y encola su calculador `OrderPriceCalculatorService`. | [OrderTriggerHandler.cls:148-149](../../force-app/main/default/classes/OrderTriggerHandler.cls#L148-L149) | Cambió, pero `Queued` no es listo → nada. **Fin de T1 (commit).** | T1 · before update |
| 8 | (no se ve; ~2 s después) | Corre el **Queueable de CPQ**: pasa la Order de `Queued` a **`Not Needed`** → `OrderTrigger`. | [OrderTrigger.trigger:10-11](../../force-app/main/default/triggers/OrderTrigger.trigger#L10-L11) | Mismo camino: `beforeUpdate`. | **T2** · before update (dentro del async de CPQ) |
| 9 | (no se ve) | → filtro | [OrderTriggerHandler.cls:146-150](../../force-app/main/default/classes/OrderTriggerHandler.cls#L146-L150) | `oldOrderByIdMap.get( newOrder.Id )`: `Queued` → `Not Needed`. **Cambió** y `isReadyToActivate` ([:128-134](../../force-app/main/default/classes/OrderTriggerHandler.cls#L128-L134)) da true (Draft + valor listo) → entra a la lista. | T2 · before update |
| 10 | (no se ve) | → **1 SOQL** | [OrderTriggerHandler.cls:74-81](../../force-app/main/default/classes/OrderTriggerHandler.cls#L74-L81), [:164-176](../../force-app/main/default/classes/OrderTriggerHandler.cls#L164-L176) | Junta los Ids en un `Set<Id>` y `getOrderIdsWithItems` hace **una** query con subquery `( SELECT Id FROM OrderItems LIMIT 1 )`: ¿tiene productos? Sí. | T2 · before update |
| 11 | (no se ve) | → activar | [OrderTriggerHandler.cls:82-87](../../force-app/main/default/classes/OrderTriggerHandler.cls#L82-L87) | `ord.Status = STATUS_ACTIVATED` **en memoria**. Salesforce lo guarda en este mismo save. **0 DML.** | T2 · before update |
| 12 | (no se ve) | La Order queda **Activated** → **Flow 2** (IC). | [Auto_Contract_Order_On_Activation.flow-meta.xml:54-72](../../force-app/main/default/flows/Auto_Contract_Order_On_Activation.flow-meta.xml#L54-L72) | Criterio: `Status` **pasa a** Activated y `Contracted = false`. | T2 · Flow after save |
| 13 | (no se ve) | Flow 2 actualiza la Order. | [Auto_Contract_Order_On_Activation.flow-meta.xml:41-43](../../force-app/main/default/flows/Auto_Contract_Order_On_Activation.flow-meta.xml#L41-L43) | `SBQQ__Contracted__c = true`. Ese update vuelve a disparar nuestro `before update`, pero el PriceCalcStatus **no cambió** → nada (**sin recursión**). CPQ encola `QueueableContractOrdersClient`. | T2 · Flow + before update |
| 14 | (~5 s después) | Corre el contracting de CPQ. | — (código de CPQ) | Crea el **Contract** + **Subscriptions** (productos con `SubscriptionPricing`) + **Assets** (los demás). | **T3** · async de CPQ |
| 15 | Abro la Order: **Status = Activated**, **Contracted** tildado. En la Account: el **Contract** con su **Subscription**. Tab **Error Logs** vacía. | — | — | Resultado final. | — |

### Camino alternativo: la Order **nace** lista (Data Loader / integración / tests)

Acá es donde aparece el **Queueable**, y es la respuesta directa al "problema del orden de CPQ".

| # | Qué pasa | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| Q1 | Se inserta una Order con `PriceCalcStatus = Not Needed` (todavía **sin productos**). | `OrderTrigger` | [OrderTrigger.trigger:12-13](../../force-app/main/default/triggers/OrderTrigger.trigger#L12-L13) | → `afterInsert`. | **after insert** (necesito el Id) |
| Q2 | (no se ve) | → filtro | [OrderTriggerHandler.cls:96-104](../../force-app/main/default/classes/OrderTriggerHandler.cls#L96-L104) | `isReadyToActivate` = true → el Id va a `orderIdToActivateSet`. **No activa acá:** no hay productos todavía. | after insert |
| Q3 | (no se ve) | → chequeo de cupo | [OrderTriggerHandler.cls:109-117](../../force-app/main/default/classes/OrderTriggerHandler.cls#L109-L117) | Si `Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()`: un Error Log por Order (`buildLog` en el loop, **un** `saveLogs` al final) y `return`. La Order se crea igual. | after insert |
| Q4 | (no se ve) | → encolar | [OrderTriggerHandler.cls:118](../../force-app/main/default/classes/OrderTriggerHandler.cls#L118) | `System.enqueueJob( new OrderActivationQueueable( orderIdToActivateSet ) )`: **un solo** job con todos los Ids. | after insert |
| Q5 | Se insertan los Order Products. Commit de la transacción. | — | — | El job encolado **recién arranca después del commit**: ahí los productos ya existen. | fin de la transacción |
| Q6 | (unos segundos después; se ve en Setup → Apex Jobs) | `execute` del Queueable | [OrderActivationQueueable.cls:20-22](../../force-app/main/default/classes/OrderActivationQueueable.cls#L20-L22), [:29-39](../../force-app/main/default/classes/OrderActivationQueueable.cls#L29-L39) | **Vuelve a consultar** las Orders (pudieron cambiar mientras esperaban): sigue en Draft + valor listo, con la misma subquery de productos. | **async** (Queueable) |
| Q7 | (no se ve) | → activar | [OrderActivationQueueable.cls:41-52](../../force-app/main/default/classes/OrderActivationQueueable.cls#L41-L52) | Si tiene productos: `Status = Activated` y **un** `Database.update( lista, false )` (si una falla, las demás siguen). Acá sí hay DML: el Queueable no está en un before. | async |
| Q8 | (no se ve) | → errores | [OrderActivationQueueable.cls:54](../../force-app/main/default/classes/OrderActivationQueueable.cls#L54) | `ErrorLogUtil.saveLogsForFailedResults(...)`: un Error Log por cada error, con StatusCode, en **un** insert. | async |
| Q9 | (no se ve) | El update del Queueable dispara nuestro `before update`. | [OrderTriggerHandler.cls:148](../../force-app/main/default/classes/OrderTriggerHandler.cls#L148) | El PriceCalcStatus no cambió en ese update → nada. **Sin recursión.** Después sigue igual que los pasos 12-15. | before update (dentro del Queueable) |

### Cómo se detecta "cambió a" Completed / Not Needed (insert vs update)

| | **Insert** | **Update** |
|---|---|---|
| ¿Hay valor viejo? | **No** (`Trigger.oldMap` es null en insert) | Sí: `oldOrderByIdMap.get( newOrder.Id )` |
| Qué significa "cambió a" | **Nacer** con el valor listo ya cuenta como "llegar" a ese valor | Valor viejo **distinto** del nuevo **y** el nuevo es listo |
| Dónde | [OrderTriggerHandler.cls:98](../../force-app/main/default/classes/OrderTriggerHandler.cls#L98): solo `isReadyToActivate( newOrder )` | [OrderTriggerHandler.cls:148-149](../../force-app/main/default/classes/OrderTriggerHandler.cls#L148-L149): `priceCalcStatusChanged && isReadyToActivate( newOrder )` |
| Regla común (DRY) | [OrderTriggerHandler.cls:128-134](../../force-app/main/default/classes/OrderTriggerHandler.cls#L128-L134) `isReadyToActivate`: `Status == 'Draft'` y `READY_PRICE_CALC_STATUSES.contains(...)` ([:31](../../force-app/main/default/classes/OrderTriggerHandler.cls#L31)) | ← la misma |

Por eso el trigger escucha `after insert` **y** `before update` ([OrderTrigger.trigger:9](../../force-app/main/default/triggers/OrderTrigger.trigger#L9)): cada contexto cubre una mitad del *"whenever it is created and … is updated"*.

---

## 4. Qué decir (guion mientras muestro el código)

1. "El requirement es activar la Order cuando su Price Calculation Status es o pasa a Completed o Not Needed. Es el eslabón que faltaba entre los dos Flows del IC: el Flow 1 hace que CPQ cree la Order y el Flow 2 la contrata cuando está activada."
2. "El problema es el orden de CPQ: inserta la Order **antes** que sus productos, y Salesforce no deja activar una Order sin productos. Si la activo en el insert, falla y se cancela toda la creación."
3. "Por eso hay dos caminos. Si la Order **nace** lista, en after insert solo junto los Ids y encolo **un** Queueable, que corre después del commit, cuando los productos ya existen, y vuelve a validar todo con datos frescos."
4. "Si **pasa a** estar lista, que es lo que realmente hace CPQ con su calculador, la activo en **before update**: es el mismo registro, así que asigno el Status en memoria, sin DML, y además no encolo nada dentro del Queueable de CPQ, que necesita su único cupo para el contracting."
5. "Para saber si 'pasó a' comparo `Trigger.new` con `Trigger.oldMap`, y la regla de qué es 'listo' está en un solo método que usan los dos caminos."
6. "Todo está bulkificado: un Set de Ids, una sola query con subquery para saber si tiene productos, un solo Queueable para 200 Orders, y los errores van a `Error_Log__c` en vez de fallar en silencio."

---

## 5. Decisiones y alternativas (resumen)

- **Update en `before update`**, sin DML ni recursión y sin encolar jobs dentro del Queueable de CPQ. Se descartó after update + `update` (DML extra, recursión, y "Too many queueable jobs" si encolaba).
- **Insert en `after insert` + Queueable**, porque en before insert no hay Id y en el insert todavía no hay productos. Se descartó activar en el insert (rollback), `@future` (no se puede llamar desde otro async ni recibe sObjects/monitoreo) y un trigger en OrderItem (activaría con la primera tanda de productos y las siguientes fallarían).
- **Apex y no Flow**, `Set` constante `READY_PRICE_CALC_STATUSES`, `== 'Draft'`, `Database.update( lista, false )` y logs en SYSTEM_MODE.

Detalle con "por qué sí / por qué no / qué pasaría" de cada una: [DEV2.md §2](../code-review/DEV2.md#2-diseño-elegido).

### Ojo con esta confusión: "el Queueable es lo que activa la Order de CPQ"

**No.** Es tentador decir "como CPQ crea la Order antes que los productos, tuve que usar un Queueable", y es **verdad para el camino del insert**. Pero el debug log del 29/09/2026 mostró que la Order de CPQ **no nace lista** (nace `Not Started`), así que en la demo el Queueable **ni se encola** y quien activa es el `before update` (paso 11). El problema del orden igual importa en el update: por eso [OrderTriggerHandler.cls:81](../../force-app/main/default/classes/OrderTriggerHandler.cls#L81) chequea que tenga productos antes de activar. Si el revisor pregunta "¿dónde está el Queueable en tu demo?", la respuesta honesta es esta. El camino del insert queda cubierto por tests y pendiente de prueba en vivo: [QA-DEV2-01](../qa-pending.md).

### Dónde aparecen los patrones base en este DEV

Explicación general de cada patrón: [00-patrones-base.md](00-patrones-base.md).

| Patrón | Dónde aparece en el DEV #2 |
|---|---|
| **Un trigger por objeto → handler** | [OrderTrigger.trigger:9-15](../../force-app/main/default/triggers/OrderTrigger.trigger#L9-L15) solo mira el contexto y delega. Entradas `public static` en [OrderTriggerHandler.cls:44-54](../../force-app/main/default/classes/OrderTriggerHandler.cls#L44-L54); lógica `private static` desde la línea 66. |
| **`Trigger.oldMap` / detectar el cambio real** | [OrderTriggerHandler.cls:146-149](../../force-app/main/default/classes/OrderTriggerHandler.cls#L146-L149). En insert no hay `oldMap`: por eso el insert tiene su propio método ([:95-119](../../force-app/main/default/classes/OrderTriggerHandler.cls#L95-L119)). |
| **Contexto correcto (before = mismo registro, after = necesito el Id)** | Before: [:85](../../force-app/main/default/classes/OrderTriggerHandler.cls#L85), asignación en memoria sin `update`. After: [:99](../../force-app/main/default/classes/OrderTriggerHandler.cls#L99), usa `newOrder.Id`, que en before insert no existe. Es el ejemplo de [00-patrones-base §3](00-patrones-base.md#3-before-vs-after-cuándo-uso-cada-uno). |
| **Bulkificación: Set, 1 SOQL, nada en loops** | `Set<Id>` en [:74-77](../../force-app/main/default/classes/OrderTriggerHandler.cls#L74-L77); **1** query en [:166-170](../../force-app/main/default/classes/OrderTriggerHandler.cls#L166-L170); **1** Queueable para todas en [:118](../../force-app/main/default/classes/OrderTriggerHandler.cls#L118); en el Queueable **1** query + **1** update ([OrderActivationQueueable.cls:33-52](../../force-app/main/default/classes/OrderActivationQueueable.cls#L33-L52)). Ver [00-patrones-base §4](00-patrones-base.md#4-bulkificación-setsmaps-soql-y-dml-fuera-de-loops). |
| **Condicional antes de la SOQL** | [OrderTriggerHandler.cls:69-71](../../force-app/main/default/classes/OrderTriggerHandler.cls#L69-L71) y [:102-104](../../force-app/main/default/classes/OrderTriggerHandler.cls#L102-L104); en el Queueable [:47-49](../../force-app/main/default/classes/OrderActivationQueueable.cls#L47-L49) antes del DML. |
| **WHERE para reducir volumen** | [OrderActivationQueueable.cls:36-38](../../force-app/main/default/classes/OrderActivationQueueable.cls#L36-L38): Ids + Draft + valores listos. |
| **Constantes / DRY** | [OrderTriggerHandler.cls:27-31](../../force-app/main/default/classes/OrderTriggerHandler.cls#L27-L31), reusadas por el Queueable ([:37-38](../../force-app/main/default/classes/OrderActivationQueueable.cls#L37-L38), [:43](../../force-app/main/default/classes/OrderActivationQueueable.cls#L43)). |
| **Async (Módulo 4): Queueable** | [OrderActivationQueueable.cls:9](../../force-app/main/default/classes/OrderActivationQueueable.cls#L9) `implements Queueable`, constructor que recibe la colección y `execute()` obligatorio. |
| **Sin fallar en silencio / límites no atrapables** | Chequeo de cupo [OrderTriggerHandler.cls:109-117](../../force-app/main/default/classes/OrderTriggerHandler.cls#L109-L117) (la `LimitException` no se puede atrapar con try/catch, así que se previene). `allOrNone = false` + Error Log en [OrderActivationQueueable.cls:52-54](../../force-app/main/default/classes/OrderActivationQueueable.cls#L52-L54). |

---

## 6. Tests

Todos usan `@testSetup` (Account + PricebookEntry), `Test.startTest()/stopTest()`, la `TestDataFactory` (`buildOrders` / `buildOrderItems`, que **no** insertan, para que el test decida cuándo) y asserts con mensaje.

### Cómo se testea un Queueable

- En un test, `System.enqueueJob` **no** corre el job en el momento: queda encolado.
- `Test.stopTest()` **fuerza a que se ejecuten** todos los jobs async encolados entre `startTest()` y `stopTest()`. Por eso los asserts van **después** del `stopTest()`.
- El orden dentro del test reproduce el problema de CPQ: `insert` de la Order (se encola el job, sin productos) → `insert` de los productos → `stopTest()` (corre el Queueable, ahora con productos). Ver [OrderTriggerHandlerTest.cls:33-36](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L33-L36).
- `startTest()` también da **governor limits nuevos** al código bajo prueba, separados de los del armado de datos. El test del cupo lo aprovecha: llena los 50 Queueables de esa ventana con jobs vacíos ([:101-105](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L101-L105)) y después inserta la Order.
- En el camino del update no hay Queueable: el `stopTest()` está por prolijidad, el resultado ya está al terminar el `update`.

| Tipo | Caso | Archivo:método |
|---|---|---|
| **Positivo (insert)** | Nace `Not Needed` + productos → Activated vía Queueable | [OrderTriggerHandlerTest.cls:30](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L30) `activateOnInsertTest` |
| **Bulk 200 (insert)** | 200 Orders → 200 Activated con **1** Queueable | [OrderTriggerHandlerTest.cls:46](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L46) `activateOnInsertBulkTest` |
| **Negativo (insert)** | Nace `Queued` → Draft | [OrderTriggerHandlerTest.cls:63](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L63) `notActivatedOnInsertWhenNotReadyTest` |
| **Negativo (insert)** | Nace lista **sin productos** → Draft, 0 Error Logs | [OrderTriggerHandlerTest.cls:80](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L80) `notActivatedOnInsertWithoutItemsTest` |
| **Edge (insert)** | Cupo de Queueables lleno → la Order se crea + 1 Error Log de `OrderTriggerHandler` | [OrderTriggerHandlerTest.cls:97](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L97) `logErrorWhenQueueableLimitReachedTest` |
| **Edge (insert)** | Salesforce rechaza la activación (Contract en Draft) → Draft + 1 Error Log de `OrderActivationQueueable` | [OrderTriggerHandlerTest.cls:123](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L123) `logErrorWhenActivationFailsTest` |
| **Positivo (update)** | `Queued` → `Completed` con productos → Activated | [OrderTriggerHandlerTest.cls:152](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L152) `activateOnUpdateTest` |
| **Bulk 200 (update)** | 200 pasan a `Completed` juntas → 200 Activated | [OrderTriggerHandlerTest.cls:168](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L168) `activateOnUpdateBulkTest` |
| **Negativo (update)** | `Queued` → `Failed` → Draft | [OrderTriggerHandlerTest.cls:187](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L187) `notActivatedOnUpdateToNotReadyValueTest` |
| **Negativo (update)** | → `Completed` sin productos → Draft, el save no falla | [OrderTriggerHandlerTest.cls:204](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L204) `notActivatedOnUpdateWithoutItemsTest` |
| **Negativo (update)** | Se edita otro campo, el status no cambia → no se reprocesa | [OrderTriggerHandlerTest.cls:222](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls#L222) `notActivatedWhenPriceCalcStatusDidNotChangeTest` |

Además, `ErrorLogUtilTest` (4 tests) cubre la utilidad de logs. Cobertura: **100%** en `OrderTrigger`, `OrderTriggerHandler`, `OrderActivationQueueable` y `ErrorLogUtil`. Build Tracker: [DEV2.md §9](../code-review/DEV2.md#9-build-tracker).

---

## 7. Edge cases cubiertos y supuestos

**Edge cases** (tabla completa en [DEV2.md §6](../code-review/DEV2.md#6-edge-cases)):

- Order que **nace** lista → se activa por el Queueable, después del commit.
- Order lista **sin productos** (insert o update) → queda en Draft, **sin error**.
- 200 Orders juntas → 1 query, 0 DML (update) / 1 Queueable (insert).
- Cupo de Queueables lleno (Order creada desde otro async) → la Order se crea igual + Error Log.
- Salesforce rechaza la activación → Draft + Error Log; las demás Orders del job se activan igual.
- La Order cambia mientras el Queueable espera → el Queueable vuelve a consultar y solo activa las que siguen cumpliendo.
- Se edita otro campo → no se reprocesa.
- **Recursión:** el update del Queueable y el del Flow 2 vuelven a disparar el `before update`, pero el PriceCalcStatus no cambió → nada.

**Supuestos** (detalle en [DEV2.md §5](../code-review/DEV2.md#5-supuestos-y-decisiones)):

- Solo se activan Orders en **Draft**.
- "Listo" = exactamente **Completed** o **Not Needed**.
- "Is updated to" = el valor **cambia**.
- La Order de CPQ nace `Not Started` (corregido con debug log); el camino del insert se mantiene por el *"whenever it is created"*.
- Limitaciones (validation rule que bloquee la activación, Order lista antes de tener productos, demora del Queueable): [DEV2.md §10](../code-review/DEV2.md#10-limitaciones-conocidas-y-pendientes-de-qa).

---

## 8. Cinco preguntas probables del revisor

**1. ¿Por qué no activás la Order directamente en el insert?**
Porque CPQ inserta la Order antes que sus productos y Salesforce no deja activar una Order sin productos. Activar en el insert daría error y cancelaría la creación entera. Por eso el insert solo encola un Queueable, que corre después del commit, cuando los productos ya están.

**2. Entonces, ¿en tu demo la activa el Queueable?**
No. La Order de CPQ nace `Not Started`, así que en el insert no está lista y no se encola nada. La activa el `before update` cuando el calculador de CPQ la pasa a `Not Needed`, segundos después, con los productos ya creados. El Queueable cubre las Orders que nacen listas (cargas o integraciones).

**3. ¿Por qué el update va en before y no en after, o en otro Queueable?**
Porque cambio un campo del mismo registro: en before lo asigno y se guarda solo, sin DML ni recursión. Además ese update ocurre dentro del Queueable de CPQ, y desde un async solo se puede encolar un job más, que CPQ necesita para el contracting. Otro Queueable mío rompería la cadena.

**4. ¿Cómo sabés que el status "pasó" a Completed y no que ya estaba así?**
En update comparo `Trigger.new` con `Trigger.oldMap` por Id y solo actúo si el valor viejo es distinto del nuevo y el nuevo es listo. En insert no hay valor viejo, así que nacer listo ya cuenta como "llegar". La regla de "listo" está en un solo método, `isReadyToActivate`.

**5. ¿Cómo testeás algo que corre en un Queueable?**
Inserto la Order y sus productos entre `Test.startTest()` y `Test.stopTest()`. El `stopTest()` obliga a ejecutar los jobs encolados, así que los asserts van después. Lo hago en ese orden (Order, después productos) para reproducir el problema de CPQ, y también pruebo el bulk de 200 con un solo job.

Más preguntas (10 en total): [DEV2.md §7](../code-review/DEV2.md#7-preguntas-probables-del-code-review).
