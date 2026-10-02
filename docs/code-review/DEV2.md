# DEV #2 — Activación automática de la Order · Resumen para el Code Review

> **Estado:** terminado, deployado y probado end-to-end en el org (29/09/2026).

---

## 1. Qué pide el requirement

> "As part of the Provisioning Team, I want the ability to automatically activate an Order record whenever it is created and the Price Calculation Status on the Order is updated to either 'Completed' or 'Not Needed'."

**En 2 líneas:** cuando una Order está lista (su `SBQQ__PriceCalcStatus__c` es o pasa a ser `Completed` o `Not Needed`), poner `Status = 'Activated'` sin que nadie lo haga a mano. Así se completa la cadena del Req #31: Closed Won → Order → **Activated** → Contracted → Contract + Subscription.

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "automatically activate an Order" | Poner `Status = 'Activated'` sin intervención humana | `OrderTriggerHandler` y `OrderActivationQueueable` |
| (B) "whenever it is created" | La Order se crea ya lista | `afterInsert` → `OrderActivationQueueable` |
| (C) "Price Calculation Status ... is updated" | El campo **cambia** a un valor listo | `beforeUpdate`, comparando con `Trigger.oldMap` |
| (D) "'Completed' or 'Not Needed'" | Solo esos dos valores | Constante `READY_PRICE_CALC_STATUSES` |

---

## 2. Diseño elegido

### Piezas

| Componente | Tipo | Rol |
|---|---|---|
| `OrderTrigger` | Apex Trigger | Único trigger de Order, sin lógica. `before update` y `after insert`. |
| `OrderTriggerHandler` | Apex Class | Métodos de entrada por contexto + lógica `private static`. |
| `OrderActivationQueueable` | Apex Class (Queueable) | Activación diferida para Orders que **nacen** listas. |
| `ErrorLogUtil` | Apex Class | Arma logs en memoria (`buildLog`) y los guarda con un solo insert (`saveLogs`). |
| `Error_Log__c` | Custom Object | Class Name, Record Id y Error Message. Con tab, layout y list view. |
| `Error_Log_Access` | Permission Set | Lectura de `Error_Log__c`. |
| `TestDataFactory` | Test utility | Datos de prueba compartidos (DRY). |
| `OrderTriggerHandlerTest`, `ErrorLogUtilTest` | Test Classes | 13 tests. |

### El problema central

Salesforce **no permite activar una Order sin Order Products**, y CPQ inserta **primero la Order y después sus productos**, en la misma transacción. Activar en el momento del insert fallaría y cancelaría la creación completa de la Order. Por eso hay dos caminos:

| Camino | Cuándo | Contexto | Cómo activa |
|---|---|---|---|
| **Update** (el camino real con CPQ) | El status **pasa a** Completed/Not Needed | `before update` | Asigna `Status` en memoria, sin DML |
| **Insert** | La Order **nace** con Completed/Not Needed | `after insert` + Queueable | El Queueable corre después del commit, cuando los productos ya existen |

### Por qué así y qué descartamos

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **Apex y no Flow** | Es un requirement DEV, y en Apex se controla mejor el orden de eventos, los límites y los errores. | Record-Triggered Flow. |
| **`before update` en el camino del update** | Cambia un campo del mismo registro, sin DML ni recursión. Además **no encola jobs** dentro del Queueable de CPQ (ver la pregunta 2). | `after update` + DML: un update extra, recursión, y en el contexto de CPQ no hay cupo para otro Queueable. |
| **`after insert` + Queueable en el camino del insert** | En before insert no hay Id. El Queueable corre recién después del commit, cuando los productos ya existen. | Activar en el insert: falla porque todavía no hay productos. |
| **Queueable y no `@future`** | Un `@future` no se puede llamar desde otro `@future` ni desde un Batch. El Queueable recibe colecciones y devuelve un Id de job que se puede monitorear. | `@future`. |
| **Trigger en Order y no en OrderItem** | Un trigger en OrderItem activaría la Order con la primera tanda de productos, y las siguientes fallarían (no se pueden agregar productos a una Order activada). | Trigger en OrderItem. |
| **`Error_Log__c` + `ErrorLogUtil`** | Los errores quedan guardados y visibles en una tab, no solo en un debug log que nadie mira. | `System.debug`. |

---

## 3. Flujo paso a paso

### Camino real: Opportunity Closed Won (verificado con debug log, 29/09/2026)

1. **El usuario pasa la Opportunity a Closed Won** → el Flow `Auto_Create_Order_On_Closed_Won` marca la Quote como Ordered.
2. **CPQ inserta la Order** con `SBQQ__PriceCalcStatus__c = 'Not Started'` → `OrderTrigger` (after insert) → `OrderTriggerHandler.afterInsert` → `enqueueActivationForNewOrders` → `isReadyToActivate` da **false** (Not Started), así que **no encola nada**.
3. **CPQ inserta los Order Products** y actualiza la Order (`Not Started` → `Not Started`) → `OrderTrigger` (before update) → `beforeUpdate` → `activateOrdersWithChangedPriceCalcStatus` → `filterOrdersReadyOnUpdate`: el valor **no cambió**, así que no hace nada.
4. **CPQ pasa la Order a `Queued`** y encola su calculador `OrderPriceCalculatorService`. Mismo recorrido del trigger: Queued no es un valor listo, así que no hace nada.
5. **Unos segundos después corre el calculador de CPQ**, que pasa la Order de `Queued` a **`Not Needed`** → `OrderTrigger` (before update) → `beforeUpdate` → `activateOrdersWithChangedPriceCalcStatus`:
   - `filterOrdersReadyOnUpdate`: el valor **cambió** y es listo (`isReadyToActivate` = true), así que la Order entra en la lista.
   - `getOrderIdsWithItems`: **una** query confirma que tiene productos.
   - Asigna `Status = 'Activated'` en memoria. Salesforce lo guarda en el mismo save, sin DML.
6. **La Order pasa a Activated** → el Flow `Auto_Contract_Order_On_Activation` la marca Contracted → CPQ encola `QueueableContractOrdersClient`.
7. **CPQ crea el Contract + la Subscription** (unos 5 segundos después).

### Camino alternativo: la Order nace lista (carga de datos o integración)

1. **Se inserta una Order con `Not Needed`** → `OrderTrigger` (after insert) → `afterInsert` → `enqueueActivationForNewOrders` → `isReadyToActivate` da **true**.
2. Chequea `Limits.getQueueableJobs()`:
   - **Si hay cupo** → `System.enqueueJob( new OrderActivationQueueable( ids ) )`.
   - **Si no hay cupo** → arma un Error Log por cada Order (`ErrorLogUtil.buildLog` + `saveLogs`) y sale. La Order se crea igual.
3. **Se insertan los productos** y la transacción hace commit.
4. **Corre `OrderActivationQueueable.execute`**:
   - Vuelve a consultar las Orders (siguen en Draft, siguen listas y tienen productos).
   - Les pone `Status = 'Activated'`.
   - Hace `Database.update( lista, false )`.
5. **`logFailures`**: si alguna falló, guarda el error en `Error_Log__c`.
6. Desde acá sigue igual que los pasos 6 y 7 del camino real.

---

## 4. Código explicado por bloques

### `OrderTrigger`

```apex
trigger OrderTrigger on Order ( before update, after insert ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        OrderTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        OrderTriggerHandler.afterInsert( Trigger.new );
    }
}
```
- **Qué hace:** mira en qué contexto se ejecuta y llama al método del handler que corresponde.
- **Por qué así:** un solo trigger por objeto (`ObjetoTrigger`), sin lógica, usando las variables de contexto y pasando `Trigger.new` / `Trigger.oldMap` (**Módulo 2**).
- **Si no estuviera:** nada llamaría al handler.

### `OrderTriggerHandler`

**Bloque 1: constantes**
```apex
public static final String STATUS_DRAFT = 'Draft';
public static final String STATUS_ACTIVATED = 'Activated';
public static final Set<String> READY_PRICE_CALC_STATUSES = new Set<String>{ 'Completed', 'Not Needed' };
```
- **Qué hace:** define los valores de la regla en un solo lugar.
- **Por qué así:** son `static final` en UPPER_CASE (**Módulo 1**). Son `public` porque el Queueable también las usa (DRY). Usamos un `Set` porque solo hay que preguntar "¿está adentro?" (`contains`).

**Bloque 2: métodos de entrada `beforeUpdate` / `afterInsert`**
- **Qué hace:** hay uno por contexto y cada uno solo delega en un método `private static`.
- **Por qué así:** es el patrón de handler del **Módulo 2**.

**Bloque 3: `activateOrdersWithChangedPriceCalcStatus` (camino update)**
- **Qué hace:**
  - Filtra las candidatas.
  - Si no hay ninguna, sale **antes de la SOQL**.
  - Junta los Ids y averigua cuáles tienen productos.
  - A esas les asigna `Status = 'Activated'`.
- **Por qué así:** cumple tres reglas de **Governor Limits**: un condicional antes de la SOQL, la SOQL afuera del loop y nada de DML en before (**Módulo 2**).

**Bloque 4: `filterOrdersReadyOnUpdate`**
- **Qué hace:** compara cada Order nueva con su versión vieja (`oldOrderByIdMap.get( newOrder.Id )`) y se queda con las que **cambiaron** a un valor listo.
- **Por qué así:** es la regla "usar `Trigger.oldMap` y correr la lógica solo si el campo cambió" (**Governor Limits**).
- **Si no estuviera:** cada edición de la Order volvería a evaluarla.

**Bloque 5: `isReadyToActivate`**
- **Qué hace:** la regla en un solo lugar. Devuelve true si la Order está en `Draft` y su status es `Completed` o `Not Needed`.
- **Por qué así:** la usan los dos caminos (DRY). Es un `if / else` con llaves, sin condicionales de una línea (**Módulo 1**).

**Bloque 6: `enqueueActivationForNewOrders` (camino insert)**
- **Qué hace:**
  - Junta las Orders que nacen listas.
  - Chequea que haya cupo de Queueables.
  - Encola **un solo** job con todos los Ids.
- **Por qué así:** se encola **un** Queueable para las 200, no uno por Order. Pasarse del límite tira una excepción que **no se puede atrapar** (**Módulo 3**) y cancelaría la creación de la Order, por eso se chequea antes.

**Bloque 7: `getOrderIdsWithItems`**
```apex
SELECT Id, ( SELECT Id FROM OrderItems LIMIT 1 ) FROM Order WHERE Id IN :orderIdSet
```
- **Qué hace:** una sola query con una subquery de hijos que trae como máximo 1 producto por Order. Solo importa saber si tiene o no.
- **Por qué así:** usa una subquery para hijos y un WHERE para traer solo lo necesario (**Módulo 1, SOQL**).

### `OrderActivationQueueable`

**Bloque 1: constructor**
- **Qué hace:** recibe el `Set<Id>` de las Orders y lo guarda.
- **Por qué así:** es un Queueable porque recibe una colección y se puede monitorear (**Módulo 4**).

**Bloque 2: `execute`**
- **Qué hace:**
  - **Vuelve a consultar** las Orders con los filtros de la regla, porque pudieron cambiar mientras esperaban.
  - Activa las que tienen productos.
  - Hace `Database.update( lista, false )`.
- **Por qué así:** trabaja con datos frescos. El `false` hace que, si una Order falla, las demás se activen igual.

**Bloque 3: `logFailures`**
- **Qué hace:** recorre los resultados **por posición** (`i`). Un `SaveResult` fallido no trae Id, así que la Order se busca en la misma posición de la lista. Arma los logs y los guarda con **un** insert.
- **Por qué así:** es el `try / catch` "sin fallar en silencio" del **Módulo 3**, aplicado a un DML parcial.

### `ErrorLogUtil`
- **`buildLog`:** arma un `Error_Log__c` en memoria, sin DML. Se usa dentro de los loops.
- **`saveLogs`:** guarda todos los logs con un solo insert, en `AccessLevel.SYSTEM_MODE`. El log es un registro del sistema y tiene que guardarse aunque el usuario no tenga permisos sobre el objeto. Si la lista está vacía, no hace nada.

### `TestDataFactory` (lo que usa el DEV #2)
- `createAccount`, `createPricebookEntry`, `createDraftContract`, `buildOrders` y `buildOrderItems`.
- Los métodos "build" no insertan, para que cada test decida cuándo hacerlo (por ejemplo, adentro de `Test.startTest()`).

---

## 5. Supuestos y decisiones

- **Solo se activan Orders en `Draft`.** El picklist `Status` del org solo tiene `Draft` y `Activated`, y `== 'Draft'` evita activar estados futuros como "Cancelled".
- **Los valores listos son exactamente `Completed` y `Not Needed`.** El picklist `SBQQ__PriceCalcStatus__c` tiene: Not Started, Not Needed, Queued, Aborted, Failed, Completed.
- **"Is updated to" = el valor cambia.** Si el campo no cambió, la Order no se reprocesa.
- **Supuesto corregido con debug log:** creíamos que la Order de CPQ nacía con `Not Needed`. Nace con `Not Started`, y la activación real la hace el **before update** cuando el calculador de CPQ la pasa a `Not Needed`.
- **Se mantiene el camino del insert** porque el requirement dice *"whenever it is created"*, y una Order puede nacer lista por otras vías (Data Loader, integraciones).
- **`with sharing`:** quien edita una Order ya puede ver sus productos, así que no hace falta saltear la seguridad.

---

## 6. Edge cases

| Caso | Cómo se maneja | Test |
|---|---|---|
| Order creada con `Not Needed` + productos | Activated (vía Queueable) | `activateOnInsertTest` |
| 200 Orders creadas juntas | 200 Activated, 1 solo Queueable | `activateOnInsertBulkTest` |
| Order creada con `Queued` | Queda en Draft | `notActivatedOnInsertWhenNotReadyTest` |
| Order creada lista sin productos | Draft, sin error | `notActivatedOnInsertWithoutItemsTest` |
| Cupo de Queueables lleno | La Order se crea igual + 1 Error Log | `logErrorWhenQueueableLimitReachedTest` |
| Salesforce rechaza la activación (Contract no activado) | Draft + 1 Error Log | `logErrorWhenActivationFailsTest` |
| `Queued` → `Completed` con productos | Activated en el momento | `activateOnUpdateTest` |
| 200 Orders pasan a `Completed` juntas | 200 Activated | `activateOnUpdateBulkTest` |
| `Queued` → `Failed` | Draft | `notActivatedOnUpdateToNotReadyValueTest` |
| → `Completed` sin productos | Draft, sin error | `notActivatedOnUpdateWithoutItemsTest` |
| Se edita otro campo y el status no cambia | No se reprocesa | `notActivatedWhenPriceCalcStatusDidNotChangeTest` |
| `saveLogs` con datos / con lista vacía | Guarda / no hace nada | `saveLogsTest`, `saveLogsEmptyListTest` |

---

## 7. Preguntas probables del Code Review

**1. ¿Por qué no activar la Order directamente en el insert?**
Porque Salesforce no deja activar una Order sin productos, y CPQ inserta la Order **antes** que sus productos. Si activáramos en el insert, Salesforce daría un error y se cancelaría la creación completa de la Order. Por eso el insert solo "anota" la activación en un Queueable, que corre después, cuando los productos ya existen.

**2. ¿Por qué el camino del update usa before y no un Queueable?**
Porque es el mismo registro: en before alcanza con asignar `Status` y Salesforce lo guarda solo, sin DML. Además, el update lo hace el calculador de CPQ, que ya es un Queueable. Desde un contexto async solo se puede encolar **un** job más, y CPQ lo usa para el contracting. Si encoláramos otro, daría "Too many queueable jobs" y se rompería la cadena.

**3. ¿Cómo sabe el trigger que el status "pasó" a Completed y no que ya estaba así?**
Compara `Trigger.new` con `Trigger.oldMap`, buscando la versión vieja por Id. Solo procesa la Order si el valor viejo es distinto del nuevo y el nuevo es Completed o Not Needed. Si alguien edita otro campo, viejo y nuevo son iguales y la Order se ignora.

**4. ¿Por qué Queueable y no `@future`?**
Un `@future` no se puede llamar desde otro `@future` ni desde un Batch, y no devuelve un Id para monitorearlo. El Queueable recibe colecciones, devuelve un Id de job que se ve en Apex Jobs y es lo que vimos en el Módulo 4 para estos casos.

**5. ¿Qué pasa si se crean 200 Orders juntas?**
Se encola **un solo** Queueable con los 200 Ids, no uno por Order. El Queueable hace una query y un update para las 200. Lo prueba `activateOnInsertBulkTest`, y en el camino del update `activateOnUpdateBulkTest`.

**6. ¿Qué pasa si no hay cupo para encolar el Queueable?**
Pasarse del límite tira una excepción que no se puede atrapar y cancelaría la creación de la Order. Por eso antes de encolar chequeamos `Limits.getQueueableJobs()`. Si no hay cupo, la Order se crea igual y queda un Error Log para revisarla a mano.

**7. ¿Por qué el Queueable vuelve a consultar las Orders en vez de usar las que recibió?**
Porque entre el insert y la ejecución del Queueable pasan unos segundos, y la Order pudo cambiar: alguien la activó o le cambió el status. Con datos frescos solo se activan las que todavía cumplen la regla.

**8. ¿Hay recursión? El Queueable hace un update de Order y eso dispara el trigger.**
El update del Queueable sí dispara el `before update`, pero el PriceCalcStatus no cambió en ese update, así que `filterOrdersReadyOnUpdate` devuelve una lista vacía y no pasa nada. No hace falta una variable estática para frenarlo.

**9. ¿Por qué `Database.update( lista, false )` y no `update lista`?**
Con `update lista`, si una Order falla se cancelan todas. Con `false`, las que pueden activarse se activan, y las que fallan devuelven su error en el `SaveResult`, que guardamos en Error Logs.

**10. ¿Por qué los logs se guardan en SYSTEM_MODE?**
El log es un registro del sistema, no del usuario. Si el usuario que disparó el proceso no tuviera permiso sobre `Error_Log__c`, el insert del log fallaría y cancelaría lo que queríamos proteger. Quién puede **ver** los logs lo sigue controlando el permission set `Error_Log_Access`.

---

## 8. Cómo se prueba en la demo

1. Crear una Opportunity en *Burlington Textiles Corp of America*.
2. Crear una Quote **Primary** con **Monthly Named Users** (producto de suscripción) y esperar unos segundos a que CPQ calcule.
3. **Submit for Approval** y, si hace falta, aprobarla. Tiene que quedar con Status **Approved**.
4. Pasar la Opportunity a **Closed Won**.
5. Esperar unos 10 segundos y abrir la Order. Tiene que verse:
   - Status **Activated**
   - **Contracted** marcado
   - En la Account, un **Contract** con su **Subscription**
6. La tab **Error Logs** tiene que estar vacía.

**Evidencia real (29/09/2026):** Opportunity "DEV2 E2E Test - Order Activation" → Q-00057 → **Order 00000120** activada ~3 s después de crearse → **Contract 00000108** + **SUB-0000011**, sin errores.

| Transacción | Hora (UTC) | PriceCalcStatus | Qué hizo nuestro código |
|---|---|---|---|
| T1: Closed Won | 19:34:24 | Order insertada con `Not Started` | `afterInsert`: no está lista → no encola nada |
| T1 | 19:34:24 | Productos insertados (`Not Started` → `Not Started`) | `beforeUpdate`: no cambió → nada |
| T1 | — | CPQ la pasa a `Queued` | — |
| T2: `OrderPriceCalculatorService` | 19:34:26 | `Queued` → **`Not Needed`** | `beforeUpdate`: cambió, está lista y tiene productos → **Activated** |
| T2 | 19:34:27 | — | Flow 2 → Contracted |
| T3: contracting de CPQ | 19:34:32 | — | Contract + Subscription creados |

---

## 9. Build Tracker

**13/13 tests pasan. Cobertura del 100%.** La última corrida fue la suite completa del org, con 30/30 tests.

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| OrderTrigger | OrderTriggerHandlerTest | 02/10/2026 | 100% |
| OrderTriggerHandler | OrderTriggerHandlerTest | 02/10/2026 | 100% |
| OrderActivationQueueable | OrderTriggerHandlerTest | 02/10/2026 | 100% |
| ErrorLogUtil | ErrorLogUtilTest | 02/10/2026 | 100% |

---

## 10. Limitaciones conocidas y pendientes de QA

1. **Validation rule que bloquee la activación.** En el camino del update activamos dentro del guardado de CPQ, así que una regla que impida activar haría fallar ese guardado. Hoy no existe ninguna.
2. **Order lista antes de tener productos.** Si una Order llega a un status listo **antes** de tener productos, no se activa sola y hay que activarla a mano. Puede pasar en cargas manuales o integraciones, no en el flujo de CPQ (según el debug log).
3. **Demora en el camino del insert.** El Queueable corre unos segundos después. Es aceptable, porque el contracting de CPQ también es asíncrono.

**Pendiente de QA:** la prueba en vivo del camino del insert (una Order que nace con `Not Needed`), con el riesgo de "Too many queueable jobs" en el contracting. Ver [`docs/qa-pending.md`](../qa-pending.md), caso **QA-DEV2-01**.
