# 00 · Patrones base del proyecto (antes de los DEV)

> **Para qué sirve este documento:** en el Code Review van a preguntar lo mismo sobre los 4 triggers: "¿por qué un trigger por objeto?", "¿por qué before?", "¿qué pasa con 200 registros?". Acá están los 5 patrones que se repiten en todo el proyecto, explicados con **`OrderTrigger` + `OrderTriggerHandler` (DEV #2)** como ejemplo, y al final dónde aparece cada uno en el resto del código.
>
> Los números de línea son del commit `bb125de` (07/10/2026).

---

## 1. Un solo trigger por objeto, sin lógica (trigger → handler)

### Qué hicimos

El trigger es un "recepcionista": se fija **en qué momento** está corriendo y le pasa los registros al método correcto del handler. No decide nada de negocio.

[OrderTrigger.trigger:9-15](../../force-app/main/default/triggers/OrderTrigger.trigger#L9-L15)

```apex
trigger OrderTrigger on Order ( before update, after insert ) {
    if ( Trigger.isBefore && Trigger.isUpdate ) {
        OrderTriggerHandler.beforeUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isInsert ) {
        OrderTriggerHandler.afterInsert( Trigger.new );
    }
}
```

Y el handler tiene dos "pisos":

- **Métodos de entrada** `public static`, uno por contexto (`beforeUpdate`, `afterInsert`), que solo llaman a la lógica — [OrderTriggerHandler.cls:44-54](../../force-app/main/default/classes/OrderTriggerHandler.cls#L44-L54).
- **Lógica** en métodos `private static` con nombres que dicen lo que hacen (`activateOrdersWithChangedPriceCalcStatus`, `enqueueActivationForNewOrders`, `filterOrdersReadyOnUpdate`, `getOrderIdsWithItems`) — [OrderTriggerHandler.cls:66-176](../../force-app/main/default/classes/OrderTriggerHandler.cls#L66-L176).

### Por qué sí

1. **Orden de ejecución predecible.** Si hay dos triggers sobre Order, Salesforce **no garantiza cuál corre primero**. Con uno solo, el orden lo decidimos nosotros dentro del handler.
2. **Se puede testear y reutilizar.** Un trigger no se puede llamar desde otro lado; una clase sí. Ejemplo real: `OrderActivationQueueable` reutiliza las constantes del handler (`OrderTriggerHandler.STATUS_DRAFT`, `READY_PRICE_CALC_STATUSES`) — [OrderActivationQueueable.cls:37-38](../../force-app/main/default/classes/OrderActivationQueueable.cls#L37-L38).
3. **Un solo lugar para leer.** Si en el Code Review preguntan "¿qué pasa cuando se actualiza una Order?", abrís el trigger, ves `beforeUpdate` y vas directo al método.
4. **Es el estándar del training** (Módulo 2): `ObjetoTrigger` + `ObjetoTriggerHandler`, `public with sharing`, entrada pública y lógica privada.

### Por qué no las otras opciones

| Alternativa | Qué pasaría |
|---|---|
| **Lógica adentro del trigger** | Funciona con un requirement, pero cuando el DEV #3 sumó el email al `QuoteTrigger` habría quedado todo mezclado en un archivo. Además no se puede llamar esa lógica desde un Batch ni reutilizar constantes. |
| **Un trigger por requirement** (ej. `QuoteExpirationTrigger` y `QuoteRenewalEmailTrigger`) | Dos triggers en el mismo objeto y contexto corren en un orden **no garantizado**. Hoy no se pisan, pero el día que sí, el bug aparece "a veces". |
| **Framework de triggers** (interfaces, clase abstracta `TriggerHandler`, fflib) | Más prolijo en proyectos grandes, pero está **fuera del nivel del training** (CLAUDE.md 3.1) y con 4 triggers no lo justifica. |

### Frase para el Code Review

> "El trigger no tiene lógica: solo mira el contexto y delega. Así hay un único punto de entrada por objeto, el orden lo controlo yo y la lógica queda en una clase que se puede testear y reutilizar."

---

## 2. `Trigger.new`, `Trigger.oldMap` y cómo detectamos un CAMBIO real

### Qué es cada cosa

| Variable | Qué tiene | En qué contextos existe |
|---|---|---|
| `Trigger.new` | `List` con los registros **con los valores nuevos** | insert, update, undelete |
| `Trigger.old` | `List` con los registros **con los valores de antes** | update, delete |
| `Trigger.oldMap` | `Map<Id, SObject>` con los valores de antes, **indexado por Id** | update, delete |

En insert **no hay** valor anterior (el registro no existía), por eso `afterInsert( Trigger.new )` recibe un solo parámetro. En delete **no hay** `Trigger.new`, por eso `SubscriptionTriggerHandler.afterDelete` recibe `Trigger.old`.

### Por qué `oldMap` y no `old`

Para comparar cada registro nuevo con **su** versión vieja, necesito encontrarlo por Id. Con un Map es un `get( Id )` directo:

[OrderTriggerHandler.cls:143-154](../../force-app/main/default/classes/OrderTriggerHandler.cls#L143-L154)

```apex
for ( Order newOrder : newOrderList ) {
    Order oldOrder = oldOrderByIdMap.get( newOrder.Id );
    // "Is updated to" means the value CHANGED. If it did not change, it is not processed again.
    Boolean priceCalcStatusChanged = newOrder.SBQQ__PriceCalcStatus__c != oldOrder.SBQQ__PriceCalcStatus__c;
    if ( priceCalcStatusChanged && isReadyToActivate( newOrder ) ) {
        readyOrderList.add( newOrder );
    }
}
```

**Por qué no `Trigger.old` (la List):** habría que confiar en que el índice `i` de `old` es el mismo registro que el índice `i` de `new`, o hacer un loop dentro de otro loop para buscarlo (200 × 200 = 40.000 comparaciones). El Map es más claro y no depende del orden.

### Por qué detectar el CAMBIO y no solo el valor

El requirement dice *"is **updated to** 'Completed' or 'Not Needed'"*. Eso es un **cambio**, no un estado.

Ejemplo concreto: una Order en Draft con `PriceCalcStatus = Not Needed` a la que alguien le edita la descripción.

- **Mirando solo el valor** (`if status == 'Not Needed'`): la activaríamos en un update que no tiene nada que ver con el precio. Y peor, cualquier update posterior volvería a evaluar la regla.
- **Mirando el cambio** (`nuevo != viejo && nuevo es listo`): como el status no cambió en esa edición, no hace nada. ✅

### El cambio real también corta la recursión

El Queueable hace `update` de las Orders ([OrderActivationQueueable.cls:52](../../force-app/main/default/classes/OrderActivationQueueable.cls#L52)), y ese update **vuelve a disparar** el `before update` del trigger. Pero en ese update el `PriceCalcStatus` **no cambió** (solo cambió el `Status`), así que `filterOrdersReadyOnUpdate` devuelve una lista vacía y el handler sale. **No hizo falta una variable estática "ya corrí"** para frenar la recursión: la comparación con `oldMap` ya lo resuelve.

| Alternativa para evitar recursión | Por qué no |
|---|---|
| `static Boolean alreadyRan` | Funciona, pero tiene una trampa: en una carga de 400 registros el trigger corre 2 veces (2 tandas de 200) y la segunda tanda **no se procesaría**. La comparación con `oldMap` no tiene ese problema. |

### Frase para el Code Review

> "Comparo `Trigger.new` contra `Trigger.oldMap` por Id para reaccionar solo cuando el campo **cambia**. Eso cumple el 'is updated to' del requirement, evita reprocesar en ediciones que no tienen nada que ver y además frena la recursión sin variables estáticas."

---

## 3. before vs after: cuándo uso cada uno

### La regla del training (Módulo 2)

| | **before** | **after** |
|---|---|---|
| **Para qué** | Cambiar campos del **mismo** registro | Tocar registros **relacionados**, o cuando necesito el **Id** |
| **DML** | **No hace falta**: cambio el campo en memoria y Salesforce lo guarda en el mismo save | **Sí hace falta** DML explícito (y los registros de `Trigger.new` son de solo lectura) |
| **¿Hay Id?** | En before insert **no** | **Sí** |
| **¿Lo ven las queries?** | No, todavía no se guardó | Sí, ya está guardado (sin commit todavía) |

### Cómo se aplica en el DEV #2 (usa los dos)

**Camino del update → `before update`** — [OrderTriggerHandler.cls:82-87](../../force-app/main/default/classes/OrderTriggerHandler.cls#L82-L87)

```apex
for ( Order ord : readyOrderList ) {
    if ( orderIdWithItemsSet.contains( ord.Id ) ) {
        // Req (A): activate. In before it is enough to set the field; Salesforce saves it.
        ord.Status = STATUS_ACTIVATED;
    }
}
```

Cambio el `Status` de la **misma** Order → before. Cero DML, cero recursión, cero gasto de límites de DML.

**Camino del insert → `after insert` + Queueable** — [OrderTriggerHandler.cls:95-119](../../force-app/main/default/classes/OrderTriggerHandler.cls#L95-L119)

Acá no alcanza con before porque:

1. Para mandar las Orders al Queueable necesito su **Id**, y en before insert todavía no existe.
2. Salesforce **no deja activar una Order sin productos**, y CPQ inserta los Order Products **después** de la Order, en la misma transacción. Si la activo en el insert, falla y se cancela toda la creación. El Queueable corre recién **después del commit**, cuando los productos ya están.

### Qué pasaría con la otra opción

| Si hubiéramos usado… | Qué pasaría |
|---|---|
| **after update + `update`** en el camino del update | Un DML extra sobre el mismo objeto, que vuelve a disparar el trigger (recursión), y gasta límites. Además ese update corre dentro del Queueable de CPQ, donde no conviene encolar ni hacer trabajo extra. |
| **before insert** en el camino del insert | No hay Id para pasar al Queueable, y activar ahí falla porque todavía no hay productos. |
| **after insert activando directo con `update`** | Mismo problema: los productos todavía no existen → error → rollback de la Order entera. |

### Frase para el Code Review

> "Before cuando cambio campos del mismo registro: es gratis, sin DML. After cuando necesito el Id o tocar otros registros. En el DEV #2 el update va en before; el insert va en after porque necesito el Id y porque la Order todavía no tiene productos, así que la activación se difiere a un Queueable."

---

## 4. Bulkificación: Sets/Maps, SOQL y DML fuera de loops

### La idea en criollo

Un trigger **nunca** recibe "una" Order: recibe una **lista** de hasta 200 (si se cargan 1.000, el trigger corre 5 veces con tandas de 200). Y los governor limits son **por transacción**, no por registro:

| Límite (transacción síncrona) | Valor |
|---|---|
| Queries SOQL | 100 |
| Sentencias DML | 150 |
| Queueables encolados | 50 |

Si hago 1 query por Order y llegan 200 Orders → 200 queries → `Too many SOQL queries: 101` → excepción que **no se puede atrapar** → rollback de toda la transacción (la Order de CPQ ni se crea).

### El patrón, paso a paso, en `activateOrdersWithChangedPriceCalcStatus`

[OrderTriggerHandler.cls:66-88](../../force-app/main/default/classes/OrderTriggerHandler.cls#L66-L88)

1. **Filtrar en memoria** (sin SOQL): `filterOrdersReadyOnUpdate` se queda solo con las que cambiaron.
2. **Condicional antes de la SOQL:** si no quedó ninguna, `return`. No gasto ni una query.
   ```apex
   if ( readyOrderList.isEmpty() ) {
       return;
   }
   ```
3. **Juntar los Ids en un `Set<Id>`** con un for simple.
4. **UNA sola query** para todas, con `WHERE Id IN :orderIdSet` — [OrderTriggerHandler.cls:166-170](../../force-app/main/default/classes/OrderTriggerHandler.cls#L166-L170):
   ```apex
   SELECT Id, ( SELECT Id FROM OrderItems LIMIT 1 )
   FROM Order
   WHERE Id IN :orderIdSet
   ```
   La subquery con `LIMIT 1` trae como máximo un producto por Order, porque solo me importa si tiene alguno.
5. **Resultado en un `Set<Id>`** (`orderIdWithItemsSet`) y en el loop final pregunto `contains( ord.Id )`, que es instantáneo.
6. **Sin DML**, porque estamos en before.

Resultado: **200 Orders = 1 query y 0 DML.** Con 1 Order, lo mismo.

### En el camino del insert

[OrderTriggerHandler.cls:96-118](../../force-app/main/default/classes/OrderTriggerHandler.cls#L96-L118)

- Junto todos los Ids en un `Set` y encolo **un solo** Queueable con todos: `System.enqueueJob( new OrderActivationQueueable( orderIdToActivateSet ) )`. **No** uno por Order (con 200 Orders serían 200 jobs y el límite es 50).
- Antes de encolar chequeo `Limits.getQueueableJobs()`: si no hay cupo, guardo un Error Log en vez de reventar.
- Los Error Logs se arman en una **lista** y se guardan con **un** insert (`ErrorLogUtil.saveLogs( errorLogList )`).

Y en el Queueable: 1 query + 1 `Database.update( lista, false )` — [OrderActivationQueueable.cls:33-54](../../force-app/main/default/classes/OrderActivationQueueable.cls#L33-L54).

### ¿Set, List o Map? Por qué cada uno

| Colección | Dónde | Por qué esa y no otra |
|---|---|---|
| `Set<Id>` | `readyOrderIdSet`, `orderIdWithItemsSet` | No admite duplicados y `contains()` es directo. Con una `List` tendría que recorrerla entera para saber si un Id está. |
| `Map<Id, Order>` | `oldOrderByIdMap` | Busco la versión vieja de cada Order por su Id con un `get()`. |
| `List<Order>` | `readyOrderList`, `orderToActivateList` | Es lo que espera el DML (`update lista`) y mantiene el orden, que importa para leer los `SaveResult` por posición. |

### Cómo lo probamos

Dos tests bulk de 200 registros en [OrderTriggerHandlerTest.cls](../../force-app/main/default/classes/OrderTriggerHandlerTest.cls):

- `activateOnInsertBulkTest` (línea 46): 200 Orders creadas juntas → las 200 activadas con **un** Queueable.
- `activateOnUpdateBulkTest` (línea 168): 200 Orders que pasan a `Completed` en el mismo update → las 200 activadas.

Si alguien metiera una query dentro del loop, estos tests romperían con `Too many SOQL queries`.

### Frase para el Code Review

> "Nunca SOQL ni DML dentro de un loop. Filtro en memoria, si no queda nada salgo antes de la query, junto los Ids en un Set, hago una sola query con `IN`, y el DML va una vez sobre una lista. 200 Orders cuestan lo mismo que una: 1 query, 0 DML. Lo pruebo con dos tests de 200 registros."

---

## 5. Los mismos patrones en los otros triggers

| Patrón | Dónde se ve |
|---|---|
| **Trigger sin lógica, delega al handler** | [QuoteTrigger.trigger:13-21](../../force-app/main/default/triggers/QuoteTrigger.trigger#L13-L21) · [ContractTrigger.trigger:11-15](../../force-app/main/default/triggers/ContractTrigger.trigger#L11-L15) · [SubscriptionTrigger.trigger:12-22](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L12-L22) |
| **Entrada `public static` → lógica `private static`** | [QuoteTriggerHandler.cls:55-75](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L55-L75) · [ContractTriggerHandler.cls:35-37](../../force-app/main/default/classes/ContractTriggerHandler.cls#L35-L37) · [SubscriptionTriggerHandler.cls:25-55](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L25-L55) |
| **Cambio real con `oldMap`** | Quote: `statusChanged` → Approved, [QuoteTriggerHandler.cls:106-109](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L106-L109) · Contract: `statusChanged` → Activated, [ContractTriggerHandler.cls:53-56](../../force-app/main/default/classes/ContractTriggerHandler.cls#L53-L56) · Subscription: 6 campos en `hasRelevantChange`, [SubscriptionTriggerHandler.cls:111-122](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L111-L122) |
| **before = mismo registro, sin DML** | Quote: `SBQQ__ExpirationDate__c = hoy + 30`, [QuoteTriggerHandler.cls:123-131](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L123-L131) · Contract: `SBQQ__RenewalForecast__c = true`, [ContractTriggerHandler.cls:58](../../force-app/main/default/classes/ContractTriggerHandler.cls#L58) |
| **after = necesito el Id / registros relacionados** | Quote after insert: el email lleva el link con el Id, [QuoteTrigger.trigger:18-19](../../force-app/main/default/triggers/QuoteTrigger.trigger#L18-L19) · Subscription: todo after porque actualiza el **Contract** (otro objeto) y la query de recuento tiene que ver el cambio ya guardado, [SubscriptionTrigger.trigger:5-6](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L5-L6) |
| **Insert sin `oldMap`, delete sin `Trigger.new`** | Quote `beforeInsert( Trigger.new )`, [QuoteTrigger.trigger:15](../../force-app/main/default/triggers/QuoteTrigger.trigger#L15) · Subscription `afterDelete( Trigger.old )`, [SubscriptionTrigger.trigger:18](../../force-app/main/default/triggers/SubscriptionTrigger.trigger#L18) |
| **Condicional antes de la SOQL** | [QuoteTriggerHandler.cls:157-159](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L157-L159) (la mayoría de las Quotes no son Renewal) · [ActiveSubscriptionCounter.cls:44-46](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L44-L46) |
| **Set de Ids + 1 query con `IN`** | Quote: [QuoteTriggerHandler.cls:150-171](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L150-L171) · Subscription: `getContractIds` arma un `Set<Id>` de Contracts sin duplicados, [SubscriptionTriggerHandler.cls:66-74](../../force-app/main/default/classes/SubscriptionTriggerHandler.cls#L66-L74), y el counter hace 1 query con subquery, [ActiveSubscriptionCounter.cls:53-60](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L53-L60) |
| **Fecha calculada una vez, fuera del loop** | [QuoteTriggerHandler.cls:127](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L127) · [ActiveSubscriptionCounter.cls:48](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L48) |
| **Un solo DML / envío sobre una lista** | Emails: un `Messaging.sendEmail( emailList, false )` para todos (límite: 10 envíos por transacción), [QuoteTriggerHandler.cls:201](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L201) · Contracts: un `Database.update`, [ActiveSubscriptionCounter.cls:146](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146) |
| **DML solo si algo cambió** | `if ( con.Active_Subscriptions__c != activeCount )`, [ActiveSubscriptionCounter.cls:90](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L90) |
| **Recursión cortada por "cambio real"** | El recuento del DEV #4 hace update de Contract → dispara `ContractTrigger` before update → el `Status` no cambió → no hace nada. Mismo mecanismo que Order + Queueable. |
| **Errores sin fallar en silencio** | `Database.update( lista, false )` + `ErrorLogUtil.saveLogsForFailedResults` en [OrderActivationQueueable.cls:52-54](../../force-app/main/default/classes/OrderActivationQueueable.cls#L52-L54) y [ActiveSubscriptionCounter.cls:146-147](../../force-app/main/default/classes/ActiveSubscriptionCounter.cls#L146-L147) · try/catch del email en [QuoteTriggerHandler.cls:200-216](../../force-app/main/default/classes/QuoteTriggerHandler.cls#L200-L216) |

### Resumen de contextos por trigger

| Trigger | Contextos | Por qué |
|---|---|---|
| `OrderTrigger` | before update, after insert | Update: cambia la misma Order. Insert: necesita el Id y esperar a los productos. |
| `QuoteTrigger` | before insert, before update, after insert | Vencimiento: mismo registro. Email: necesita el Id para el link. |
| `ContractTrigger` | before update | Solo tilda un campo del mismo Contract; CPQ hace el resto. No hay before insert porque un Contract no puede nacer Activated. |
| `SubscriptionTrigger` | after insert/update/delete/undelete | Actualiza **otro** objeto (Contract) y necesita que la query vea el cambio ya guardado. |

---

## Preguntas rápidas que pueden caer

**1. ¿Por qué no usaste un framework de triggers?**
Con 4 triggers no lo justifica y está fuera de lo que vimos en el training. El patrón trigger → handler con métodos por contexto ya da un punto de entrada único y lógica testeable. Si el proyecto creciera a decenas de objetos, ahí sí lo evaluaría.

**2. ¿Qué pasa si se cargan 1.000 Orders con Data Loader?**
Salesforce parte la carga en tandas de 200 y corre el trigger una vez por tanda. Cada tanda gasta 1 query y 0 DML en el camino del update, así que no hay riesgo de límites. Lo prueban los tests bulk de 200.

**3. ¿Por qué `Trigger.oldMap` y no `Trigger.old`?**
Porque necesito la versión vieja de **cada** registro y la busco por Id con un `get()`. Con la lista tendría que depender del orden o hacer un loop adentro de otro.

**4. ¿Cómo evitás la recursión?**
Reaccionando solo cuando el campo **cambia**. El update del Queueable vuelve a disparar el trigger, pero el `PriceCalcStatus` no cambió, así que no hace nada. No uso una variable estática porque con más de 200 registros dejaría la segunda tanda sin procesar.

**5. ¿Por qué en before no hacés `update`?**
Porque en before los registros de `Trigger.new` todavía no se guardaron: si les cambio un campo, Salesforce lo guarda en el mismo save. Un `update` ahí daría error y además no hace falta.

**6. ¿Por qué el `SubscriptionTrigger` es todo after?**
Porque el que cambia es el Contract, que es otro objeto, y eso requiere DML explícito. Además el recuento hace una query y tiene que ver la Subscription ya guardada (en after delete, ya sin la borrada).

**7. ¿Qué pasa si una Order de un lote de 200 falla al activarse?**
En el Queueable uso `Database.update( lista, false )`: las otras 199 se activan igual, y la que falló queda registrada en `Error_Log__c` con su error. No falla en silencio ni cancela las demás.
