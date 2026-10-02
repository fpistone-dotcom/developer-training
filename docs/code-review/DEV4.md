# DEV #4 — Contador de Subscriptions activas en el Contract · Resumen para el Code Review

> **Estado:** terminado, deployado y probado en el org (02/10/2026). Backfill corrido a mano y job nocturno programado a las 2:00.

---

## 1. Qué pide el requirement

> "As a Sales User, I need a field on the Contract that quickly identifies how many active Subscriptions are currently related to the Contract."

**En 2 líneas:** un campo número en el Contract que diga cuántas de sus Subscriptions están activas **hoy**. Tiene que actualizarse solo, tanto cuando alguien toca una Subscription como cuando una vence o empieza con el paso del tiempo.

| Parte | Qué significa | Dónde se cubre |
|---|---|---|
| (A) "a field on the Contract" | Campo nuevo `Contract.Active_Subscriptions__c` (Number, solo lectura en el layout) | Metadata + `ActiveSubscriptionCounter.recountActiveSubscriptions` |
| (B) "how many Subscriptions ... related" | Una por **Subscription original**: las revisiones de Amendment no suman registros, cambian la cantidad | `ActiveSubscriptionCounter.countActiveSubscriptions` |
| (C) "active ... currently" | Vigente **hoy**: ya empezó, no venció, no fue terminada. Se mantiene al día con el paso del tiempo | `ActiveSubscriptionCounter.isInForceToday` + `ActiveSubscriptionRecountBatch` |
| (D) "currently related" | Si se crea, edita, borra, recupera o **cambia de Contract** una Subscription, el número se ajusta | `SubscriptionTrigger` + `SubscriptionTriggerHandler` |

---

## 2. Diseño elegido

### Piezas

| Componente | Tipo | Rol |
|---|---|---|
| `Contract.Active_Subscriptions__c` | Custom Field (Number 18,0, default 0) | Guarda el número. |
| `Training Contract Layout` | Page Layout (el que usan System Administrator y Direct Sales) | Muestra el campo como **Read-Only**, debajo de Contract Term. |
| `Active_Subscriptions_Access` | Permission Set | Lectura del campo. Asignado a frandev (admin) y sh.dsales (Direct Sales). |
| `SubscriptionTrigger` | Apex Trigger | Único trigger propio de `SBQQ__Subscription__c`, sin lógica. after insert / update / delete / undelete. |
| `SubscriptionTriggerHandler` | Apex Class | Decide **qué** Contracts recalcular. |
| `ActiveSubscriptionCounter` | Apex Class | **El recuento** (la regla de "activa" y los Amendments). Lo usan el trigger y el Batch (DRY). |
| `ActiveSubscriptionRecountBatch` | Apex Class (Batchable) | Recuenta todos los Contracts, de a 200. |
| `ActiveSubscriptionRecountScheduler` | Apex Class (Schedulable) | "Despertador" a las 2:00: solo lanza el Batch. Job: *Active Subscriptions Recount - Nightly*. |
| `ErrorLogUtil` / `Error_Log__c` | Reutilizados del DEV #2 | Registro de errores si falla el update de un Contract. |
| `TestDataFactory` (`createProduct`, `createContract`, `buildSubscriptions`) | Test utility | Datos de prueba compartidos. |
| 4 Test Classes | Test | 23 tests (ver sección 9). |

En el org también existe `SBQQ.SubscriptionAfter` (trigger de CPQ). No es nuestro, no se puede modificar y convive con el nuestro.

### Por qué así y qué descartamos

| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| **Trigger en Subscription (no Roll-Up Summary)** | `SBQQ__Contract__c` es un **Lookup**. Los Roll-Up Summary nativos solo existen en **Master-Detail**. Además es un campo del paquete (no se puede cambiar) y un Roll-Up no puede filtrar por `TODAY()`. | **Roll-Up Summary:** imposible. **Flow:** delete y recuento con lógica de fechas quedan incómodos (y el requirement es DEV). **DLRS:** paquete externo, tampoco resuelve el paso del tiempo. |
| **Recontar desde cero, no sumar/restar 1** | Para los mismos datos da siempre el mismo resultado. Un contador incremental se desfasa con el primer error, con una carga de datos o con un registro movido. | Incremental (`+1` / `-1`): frágil. |
| **Todos los contextos en after** | Modificamos un registro **relacionado** (el Contract) con DML, y la query tiene que ver el cambio ya guardado (en after delete la borrada ya no aparece). | Before: el Id no existe en before insert, y en before delete la query todavía vería la Subscription. |
| **Clase propia para el recuento** | Lo usan dos caminos (trigger y Batch). Si la regla de "activa" cambia, cambia en **un solo lugar** (DRY). | Copiar la lógica en el Batch: dos lugares que mantener. |
| **Batch + Scheduler nocturno** | Una Subscription puede **empezar** o **vencer** sin que nadie la edite (un Amendment con fecha futura, el fin del Contract). El trigger no se entera: es el mismo problema del DEV #1. | **Solo trigger:** el número queda viejo hasta que alguien edite algo, y no cumple "currently". **Batch solo de "los que cruzaron una fecha hoy":** query más compleja, y si una noche falla esos Contracts quedan mal para siempre. |
| **El Batch recorre TODOS los Contracts** | Query más simple. De paso completa con 0 los Contracts creados antes del campo (el default solo aplica a registros nuevos). Solo hace update si el número cambió. | Solo Contracts con Subscriptions (semi-join): no corrige un Contract que quedó con un número viejo y sin Subscriptions. |
| **A las 2:00** | Decisión de Francisco: no coincidir con el job del DEV #1 (1:00). | — |
| **Opción C para Amendments** | Ver sección 5. Para un vendedor, un Amendment cambia la cantidad de **una** Subscription, no crea otra. | Contar registros (daría 3 en el caso de la demo), solo cantidad > 0 (daría 2), sumar cantidades (eso son licencias, no Subscriptions). |

---

## 3. Flujo paso a paso

### 3.1 La lógica de negocio (sin código), con el caso de la demo

Contract de 12 meses (1/10/2026 → 30/09/2027) con dos productos de suscripción: **Monthly Named Users × 125** (SUB-A) y un segundo producto, por ejemplo **Soporte × 1** (SUB-S).

| Momento | Qué pasa en el negocio | Registros de Subscription en el Contract | Número en el Contract |
|---|---|---|---|
| **Mes 0: se contrata** | CPQ crea una Subscription por producto | SUB-A 125, SUB-S 1 | **2** |
| **Se hace el Amendment +100 con inicio en el mes 6** | CPQ **no** toca SUB-A: crea **SUB-B = +100**, que apunta a SUB-A, con inicio en el mes 6 | + SUB-B +100 (futura) | **2**: SUB-B todavía no empezó, y aunque empezara es parte de SUB-A |
| **Se hace el Amendment −10 con inicio en el mes 9** | CPQ crea **SUB-C = −10**, que apunta a SUB-A, con inicio en el mes 9 | + SUB-C −10 (futura) | **2** |
| **Mes 6 (nadie edita nada)** | SUB-B empieza. Neto de SUB-A: 125 + 100 = 225 > 0 | igual | **2** (lo confirma el Batch de esa noche) |
| **Mes 9 (nadie edita nada)** | SUB-C empieza. Neto de SUB-A: 125 + 100 − 10 = **215** > 0 | igual | **2** |
| **Alguien borra SUB-S** | El trigger (after delete) recuenta el Contract | SUB-A, B, C | **1** |
| **La recupera de la papelera** | El trigger (after undelete) recuenta | SUB-A, B, C, S | **2** |
| **Un Amendment da de baja todo el Soporte** (−1) | Neto de SUB-S = 0: deja de contar desde la fecha de la baja | + revisión −1 de SUB-S | **1** |
| **Pasa el 30/09/2027 (nadie edita nada)** | Todas vencen con el Contract. A las 2:00 el Batch recuenta | igual | **0** |

**La regla en una frase:** se cuenta **una vez cada Subscription original** cuya cantidad neta vigente hoy (la original más las revisiones que ya empezaron) sea mayor a 0. "Vigente hoy" = ya empezó, no venció y no fue terminada.

### 3.2 El código en orden cronológico

**Camino 1: el trigger (alguien crea, edita, borra o recupera una Subscription)**

1. **Usuario, CPQ o integración** guarda una o varias Subscriptions (por ejemplo, el contracting de CPQ inserta SUB-B).
2. **`SubscriptionTrigger`** (after insert / update / delete / undelete) mira el contexto y llama al método de entrada del handler:
   - insert → `SubscriptionTriggerHandler.afterInsert( Trigger.new )`
   - update → `afterUpdate( Trigger.new, Trigger.oldMap )`
   - delete → `afterDelete( Trigger.old )` (en delete no hay `Trigger.new`)
   - undelete → `afterUndelete( Trigger.new )`
3. **`SubscriptionTriggerHandler`** arma el `Set<Id>` de Contracts a recalcular:
   - insert / delete / undelete → **`getContractIds`**: los Contracts de las Subscriptions (sin vacíos ni repetidos).
   - update → **`getContractIdsWithRelevantChanges`**: para cada Subscription, **`hasRelevantChange`** compara con `Trigger.oldMap` (Contract, Quantity, fechas propias, TerminatedDate, RevisedSubscription). Si nada relevante cambió, la saltea. Si cambió, agrega el Contract **nuevo y el viejo** (por si se movió).
4. → ⭐ **`ActiveSubscriptionCounter.recountActiveSubscriptions( contractIdSet )`** (el método compartido):
   - a. Si el Set está vacío → `return` (0 queries).
   - b. **1 SOQL:** los Contracts con su `Active_Subscriptions__c` actual y, en una subquery, sus Subscriptions (cantidad, original, fechas fórmula, terminación).
   - c. Por cada Contract, recorre sus Subscriptions: **`isInForceToday`** descarta las que no están vigentes hoy; las vigentes suman su cantidad en un `Map<Id, Decimal>` cuya clave es la **original** (la propia Subscription o su `SBQQ__RevisedSubscription__c`).
   - d. **`countActiveSubscriptions`** cuenta cuántas originales tienen neto > 0.
   - e. Si el número es distinto al guardado, el Contract va a la lista de updates.
5. → **`updateContracts`**: **1 DML** (`Database.update( lista, false )`). Si algún Contract falla → `ErrorLogUtil.buildLog` + `ErrorLogUtil.saveLogs` (1 insert). La transacción del usuario (o el contracting de CPQ) **no se cancela**.
6. **Resultado:** el Contract muestra el número nuevo al refrescar. El update del Contract dispara los triggers de CPQ sobre Contract, pero no los nuestros (no hay trigger propio en Contract), así que no hay recursión.

**Camino 2: el nocturno (el Scheduler despierta a las 2:00)**

1. **2:00 (zona del usuario que lo programó)** → Salesforce ejecuta el job *Active Subscriptions Recount - Nightly* → **`ActiveSubscriptionRecountScheduler.execute`** → `Database.executeBatch( new ActiveSubscriptionRecountBatch() )`.
2. **`ActiveSubscriptionRecountBatch.start`**: una query `SELECT Id FROM Contract` (todos).
3. Salesforce parte el resultado en tandas de 200 y llama a **`execute`** por cada una (cada tanda con sus propios governor limits): arma el `Set<Id>` de la tanda y llama a…
4. → ⭐ **`ActiveSubscriptionCounter.recountActiveSubscriptions( contractIdSet )`**: **el mismo método del paso 4 del camino 1**, con los mismos pasos a–e y `updateContracts`. Como "hoy" ahora es otro día, detecta las que empezaron o vencieron.
5. **`finish`**: no hace nada. El job vuelve a dormir hasta la noche siguiente.

⭐ = el punto donde los dos caminos usan **el mismo** método.

### 3.3 La misma explicación, bien simple (para repasar)

**Idea general.** El Contract tiene un campo, *Active Subscriptions*, que dice cuántas Subscriptions activas tiene. Ese número tiene que actualizarse en dos situaciones:
1. **Cuando alguien toca una Subscription** (la crea, la edita, la borra o la recupera). De eso se encarga el **trigger**.
2. **Cuando pasa el tiempo** y una Subscription vence o empieza sola, sin que nadie la toque. De eso se encarga el **job de la noche**.

Los dos caminos usan **la misma función para contar** (⭐). Así la regla de "qué es activa" está escrita en un solo lugar.

#### Camino 1: alguien toca una Subscription

**Paso 1: alguien guarda una Subscription.** Salesforce ejecuta solo **`SubscriptionTrigger`**.
- Un *trigger* es código que se ejecuta automáticamente cuando se guarda un registro. El nuestro no hace cuentas: se fija **qué acción pasó** y avisa al handler.
- `Trigger.isInsert` / `isUpdate` / `isDelete` / `isUndelete` dicen si se creó, editó, borró o recuperó.
- `Trigger.isAfter` indica que estamos **después** del guardado. Usamos "after" porque vamos a modificar **otro** registro (el Contract), y para contar necesitamos que el cambio ya esté guardado.
- `Trigger.new` es la lista de Subscriptions **como quedaron**. `Trigger.old` / `Trigger.oldMap` son **como estaban antes**. En un delete solo existe `Trigger.old`.

**Paso 2: averiguar qué Contracts hay que recalcular.** Lo hace **`SubscriptionTriggerHandler`** ("el que se encarga" del trigger).
- Si fue crear, borrar o recuperar, usa **`getContractIds`**: recorre las Subscriptions y guarda el Id de su Contract en un **`Set`**. Un Set es una lista **sin repetidos**: si 3 Subscriptions son del mismo Contract, el Id queda una sola vez.
- Si fue editar, usa **`getContractIdsWithRelevantChanges`**. Para cada Subscription llama a **`hasRelevantChange`** ("¿tuvo un cambio importante?"), que compara viejo contra nuevo en los campos que pueden cambiar el conteo: Contract, cantidad, fechas, terminación y Subscription original.
  - Si solo cambió, por ejemplo, el precio, esa Subscription se **ignora**.
  - Si **se movió de Contract**, guarda los dos: el viejo (pierde una) y el nuevo (gana una).

**Paso 3 ⭐: contar.** Lo hace **`ActiveSubscriptionCounter.recountActiveSubscriptions`** ("recontar las Subscriptions activas"). No suma ni resta 1: **cuenta todo de nuevo**, así nunca se desfasa.
- **3a.** `if ( contractIdSet.isEmpty() ) { return; }`: si no hay Contracts, sale sin gastar una consulta.
- **3b.** **Una sola consulta (SOQL)** trae los Contracts con el número que tienen guardado y, en una **subquery** (`SBQQ__Subscriptions__r`), sus Subscriptions hijas. Nunca consultamos dentro de un `for`, porque el límite es de 100 consultas por transacción.
- **3c.** Para cada Subscription, **`isInForceToday`** ("¿está en vigencia hoy?") revisa tres cosas: `hasStarted` (ya empezó), `hasNotEnded` (no terminó, o no tiene fin) y `isNotTerminated` (no la dieron de baja). Si alguna falla, `continue` pasa a la siguiente.
- **3d.** Junta los Amendments con su original. Si la Subscription tiene `SBQQ__RevisedSubscription__c`, es un Amendment y su cantidad se suma a la **original**. Las sumas se guardan en un **`Map`** (una agenda "original → cantidad"), llamado `netQuantityByOriginalIdMap`. En la demo queda SUB-A → 125 + 100 − 10 = **215**.
- **3e.** **`countActiveSubscriptions`** cuenta las originales con cantidad > 0 (215 > 0, así que cuenta 1). Si el número es **igual** al que ya tenía el Contract, no se guarda nada.

**Paso 4: guardar.** Lo hace **`updateContracts`**: `Database.update( lista, false )` hace un solo guardado para todos. El `false` significa "si uno falla, guardá igual los demás", así no se cancela lo que hacía el usuario o CPQ. Los errores van al objeto **Error Log** con **`ErrorLogUtil`**, la misma clase que en el DEV #2.

**Resultado:** el usuario refresca el Contract y ve el número nuevo.

#### Camino 2: el job de la noche

1. **Suena el despertador a las 2:00.** **`ActiveSubscriptionRecountScheduler`** (un *Scheduler* es una clase que Salesforce ejecuta a una hora fija). `'0 0 2 * * ?'` significa "todos los días a las 2:00". Su `execute` solo arranca el Batch.
2. **Trae todos los Contracts.** **`ActiveSubscriptionRecountBatch.start`**. Un *Batch* procesa mucha cantidad de registros **en tandas de 200**, y cada tanda tiene sus propios límites.
3. **⭐ Cuenta cada tanda.** `execute` arma el `Set` con los 200 Ids y llama a **la misma** `ActiveSubscriptionCounter.recountActiveSubscriptions`. Como "hoy" es otro día, detecta solas las Subscriptions que vencieron o empezaron.
4. **Termina.** `finish` está vacío. El job vuelve a dormir hasta la noche siguiente.

#### Una línea por archivo

| Archivo | Qué hace, en simple |
|---|---|
| `SubscriptionTrigger` | Se da cuenta de que alguien tocó una Subscription y avisa |
| `SubscriptionTriggerHandler` | Arma la lista de Contracts a recalcular |
| `ActiveSubscriptionCounter` ⭐ | Cuenta las activas y guarda el número (lo usan los dos caminos) |
| `ActiveSubscriptionRecountScheduler` | Despertador de las 2:00 |
| `ActiveSubscriptionRecountBatch` | Recorre todos los Contracts de a 200 y llama al contador |

---

## 4. Código explicado por bloques

### `SubscriptionTrigger`

```apex
trigger SubscriptionTrigger on SBQQ__Subscription__c ( after insert, after update, after delete, after undelete ) {
    if ( Trigger.isAfter && Trigger.isInsert ) {
        SubscriptionTriggerHandler.afterInsert( Trigger.new );
    } else if ( Trigger.isAfter && Trigger.isUpdate ) {
        SubscriptionTriggerHandler.afterUpdate( Trigger.new, Trigger.oldMap );
    } else if ( Trigger.isAfter && Trigger.isDelete ) {
        SubscriptionTriggerHandler.afterDelete( Trigger.old );
    } else if ( Trigger.isAfter && Trigger.isUndelete ) {
        SubscriptionTriggerHandler.afterUndelete( Trigger.new );
    }
}
```
- **Qué hace:** mira el contexto y delega. En delete usa `Trigger.old` porque no existe `Trigger.new`.
- **Regla del training:** un trigger por objeto, `ObjetoTrigger`, sin lógica, con variables de contexto (**Módulo 2**). After porque toca un registro relacionado (**Módulo 2**).

### `SubscriptionTriggerHandler`

**Bloque 1: entradas `afterInsert` / `afterUpdate` / `afterDelete` / `afterUndelete`**
- **Qué hace:** cada una arma el Set de Contracts y llama a `ActiveSubscriptionCounter.recountActiveSubscriptions`.
- **Regla del training:** métodos de entrada `public static` por contexto que llaman a `private static` (**Módulo 2**).

**Bloque 2: `getContractIds`**
```apex
for ( SBQQ__Subscription__c sub : subscriptionList ) {
    if ( sub.SBQQ__Contract__c != null ) {
        contractIdSet.add( sub.SBQQ__Contract__c );
    }
}
```
- **Qué hace:** junta los Contracts sin repetir (por eso un `Set`) y sin vacíos.
- **Regla del training:** for mejorado, `Set<Id>` para bulkificar (**Módulo 1, Governor Limits**).

**Bloque 3: `getContractIdsWithRelevantChanges` + `hasRelevantChange`**
- **Qué hace:** en un update, solo pide recálculo si cambió un campo que afecta el conteo. Si cambió el Contract, agrega el **nuevo y el viejo**.
- **Por qué así:** "usar `Trigger.oldMap` para correr la lógica solo si el campo cambió" (**Governor Limits**). Compara los campos **reales** (`SBQQ__SubscriptionStartDate__c`, etc.) y no las fórmulas `SBQQ__StartDate__c`, porque las fórmulas no se recalculan en `Trigger.new`.

### `ActiveSubscriptionCounter`

**Bloque 1: guard + query**
```apex
if ( contractIdSet.isEmpty() ) { return; }
...
for ( Contract con : [
    SELECT Id, Active_Subscriptions__c,
        ( SELECT Id, SBQQ__RevisedSubscription__c, SBQQ__Quantity__c,
                 SBQQ__StartDate__c, SBQQ__EndDate__c, SBQQ__TerminatedDate__c
          FROM SBQQ__Subscriptions__r )
    FROM Contract
    WHERE Id IN :contractIdSet
] ) {
```
- **Qué hace:** una sola query para todos los Contracts, con sus Subscriptions en una subquery (relación hija `SBQQ__Subscriptions__r`).
- **Regla del training:** condicional antes de la SOQL, WHERE, subquery para hijos, query afuera de loops (**Módulo 1 SOQL, Governor Limits**).
- **Por qué las fórmulas:** `SBQQ__StartDate__c` / `SBQQ__EndDate__c` ya resuelven "la fecha propia o, si está vacía, la del Contract". En el org **todas** las Subscriptions tienen su fecha de fin vacía, así que la real sale del Contract.
- **Por qué `for` sobre la subquery:** si un Contract tuviera más de 200 Subscriptions, pasar la lista entera a otro método falla. Con el `for`, Salesforce la trae por partes.

**Bloque 2: agrupar por la original (opción C)**
```apex
Id originalId = sub.Id;
if ( sub.SBQQ__RevisedSubscription__c != null ) {
    originalId = sub.SBQQ__RevisedSubscription__c;
}
...
netQuantityByOriginalIdMap.put( originalId, netQuantity + quantity );
```
- **Qué hace:** suma la cantidad de cada Subscription vigente bajo el Id de su original (125 + 100 − 10).
- **Por qué así:** `Map<Id, Decimal>` con el patrón `valorPorClaveMap` (**Módulo 1**). Quantity es Double en el campo, así que se usa `Decimal`. `null` se trata como 0.

**Bloque 3: `isInForceToday`**
```apex
Boolean hasStarted = sub.SBQQ__StartDate__c == null || sub.SBQQ__StartDate__c <= today;
Boolean hasNotEnded = sub.SBQQ__EndDate__c == null || sub.SBQQ__EndDate__c >= today;
Boolean isNotTerminated = sub.SBQQ__TerminatedDate__c == null || sub.SBQQ__TerminatedDate__c > today;
```
- **Qué hace:** la definición de "activa" en un solo lugar. Una fecha vacía no excluye (por ejemplo, un Contract evergreen no tiene fin).
- **Regla del training:** `if / else` con llaves y variables con nombre descriptivo (**Módulo 1**). `today` se calcula una vez, afuera del loop.

**Bloque 4: `countActiveSubscriptions`**
- **Qué hace:** cuenta los valores del Map con neto > 0.

**Bloque 5: solo actualizar si cambió**
```apex
if ( con.Active_Subscriptions__c != activeCount ) { ... contractToUpdateList.add( con ); }
```
- **Por qué así:** menos DML y no se disparan de gusto los triggers de CPQ sobre Contract. También corta cualquier posible ida y vuelta: si nada cambió, no hay update.

**Bloque 6: `updateContracts`**
- **Qué hace:** un solo `Database.update( lista, false )`. Recorre los resultados **por posición** (un resultado fallido no trae el Id) y guarda los errores con un solo insert.
- **Regla del training:** sin DML en loops, una sola DML por objeto, sin fallar en silencio (**Governor Limits, Módulo 3**). Mismo patrón que el DEV #1 y el DEV #2.

### `ActiveSubscriptionRecountBatch`
- **`start`:** `SELECT Id FROM Contract`, solo el Id porque el recuento hace su propia query.
- **`execute`:** Set de Ids de la tanda → `ActiveSubscriptionCounter.recountActiveSubscriptions` (DRY).
- **`finish`:** vacío, porque la interfaz lo exige.
- **Regla del training:** Batch para gran volumen. En tests, `execute()` corre una vez (**Módulo 4**). `Database.Batchable<SObject>` lo exige la interfaz (no es un genérico elegido por nosotros). Sin `Database.Stateful`.

### `ActiveSubscriptionRecountScheduler`
```apex
public static final String JOB_NAME = 'Active Subscriptions Recount - Nightly';
public static final String CRON_EXPRESSION = '0 0 2 * * ?';
public void execute( SchedulableContext sc ) {
    Database.executeBatch( new ActiveSubscriptionRecountBatch() );
}
```
- **Regla del training:** `Schedulable` que delega la lógica en otra clase (**Módulo 4**).

### `TestDataFactory` (lo agregado para el DEV #4)
- **`createProduct()`:** `createPricebookEntry` ahora lo reutiliza (DRY).
- **`createContract( accountId, startDate, contractTerm )`:** con `contractTerm = null` queda evergreen.
- **`buildSubscriptions( contractId, productId, n, quantity )`:** sin fechas propias, como las que crea CPQ en el org. Acepta cantidad negativa para simular una baja de Amendment.

---

## 5. Supuestos y decisiones

Confirmadas por Francisco el 02/10/2026:

1. **"Activa" = vigente hoy:** inicio vacío o ≤ hoy, fin vacío o ≥ hoy, `SBQQ__TerminatedDate__c` vacío o > hoy. Se usan las fórmulas de fecha de CPQ (fecha propia o la del Contract).
2. **No se mira el estado del Contract** (Draft / Activated). Activar el Contract es parte del DEV #3. Un Contract en Draft con Subscriptions vigentes muestra su número.
3. **Amendments, opción C:** una por Subscription original con cantidad neta vigente > 0.
4. **Batch + Scheduler a las 2:00**, para no coincidir con el job del DEV #1 (1:00).
5. **Campo, layout y permission set** son parte del DEV #4 (IC autorizado).

**Prueba de Amendment en el org (02/10/2026, Contract 00000108), hecha antes de programar:**

| Paso | Cómo | Resultado |
|---|---|---|
| Amendment 1 | `SBQQ.ServiceRouter.load('SBQQ.ContractManipulationAPI.ContractAmender', ...)` (lo mismo que el botón **Amend**) → Q-00080. Inicio 2027-04-01, 125 → 225 → Ordered | Order 00000121 activada por el DEV #2 y contratada por el Flow 2 → **SUB-0000012 = +100** |
| Amendment 2 | Igual → Q-00081 (CPQ mostró **una** línea de 225 que apunta a SUB-0000011). Inicio 2027-07-01, 225 → 215 → Ordered | Order 00000122 → **SUB-0000013 = −10** |

| Name | Quantity | RevisedSubscription | StartDate | EndDate | TerminatedDate |
|---|---|---|---|---|---|
| SUB-0000011 | 125 | — | 2026-10-01 | 2027-09-30 | — |
| SUB-0000012 | 100 | SUB-0000011 | 2027-04-01 | 2027-09-30 | — |
| SUB-0000013 | −10 | SUB-0000011 | 2027-07-01 | 2027-09-30 | — |

- **⚠️ (a) Confirmado:** las revisiones apuntan **siempre a la original**, también en el segundo Amendment (no apuntan a SUB-0000012).
- **⚠️ (b) Parcial:** una **baja parcial** (−10) **no** completa `SBQQ__TerminatedDate__c`. La baja **total** (a 0) no se probó para no dejar en 0 el Contract de la demo. La opción C la cubre de las dos formas: neto 0 deja de contar y, si CPQ completara la fecha, `isInForceToday` también la excluye. Pendiente → **QA-DEV4-02**.
- **CPQ permite hacer Amendments de un Contract en Draft:** no hizo falta activarlo ni tocar el IC.

**Otros supuestos:**
- **`with sharing`:** el sharing de Contract y Subscription es **Public Read/Write** (interno), así que el recuento ve todas las Subscriptions. Si en el futuro se pasa a Private, habría que revisarlo.
- **"Hoy"** = `Date.today()` en la zona horaria del usuario que dispara la transacción (o del que programó el job).
- **Subscriptions sin Contract** se ignoran.
- **Si se borra una Subscription original que tiene revisiones** (caso raro: CPQ no borra Subscriptions), Salesforce normalmente vacía el lookup `SBQQ__RevisedSubscription__c` de sus revisiones. Cada revisión pasa a contarse sola: la de +100 cuenta 1 y la de −10 no. Al recuperarla de la papelera, Salesforce restaura el lookup y vuelve a ser 1 en total.
- **El campo es de solo lectura** para los usuarios (layout Read-Only y permission set sin edit). Lo escribe Apex, que no está limitado por los permisos de campo.

---

## 6. Edge cases

| Caso | Cómo se maneja | Test |
|---|---|---|
| Subscription vigente (fechas del Contract) | Cuenta 1 | `activeSubscriptionCountsTest` |
| Empieza mañana | No cuenta | `futureSubscriptionNotCountedTest` |
| Venció ayer / vence hoy (borde) | Ayer no cuenta, hoy sí | `endDateBoundaryTest` |
| Terminada hoy / se termina mañana (borde) | Hoy no cuenta, mañana sí | `terminatedDateBoundaryTest` |
| Contract evergreen (sin fecha de fin) | Cuenta | `evergreenContractTest` |
| Amendment +100 y −10 (caso de la demo) | 1, no 3 | `amendmentRevisionsCountOnceTest` |
| Amendment que baja a 0 | 0 | `fullCancellationNotCountedTest` |
| Baja total con fecha futura | Hoy sigue contando | `futureCancellationStillCountsTest` |
| Set vacío | 0 queries | `emptySetSkipsQueryTest` |
| El número ya es correcto | 0 DML | `unchangedCountSkipsUpdateTest` |
| Insert en dos Contracts a la vez | Cada uno con su número | `insertTest` |
| Update que cambia la vigencia (TerminatedDate) | Recalcula | `updateRelevantFieldTest` |
| Update de un campo que no importa (precio) | **No** recalcula | `updateIrrelevantFieldTest` |
| La Subscription se mueve de Contract | Se recalculan los dos | `moveToAnotherContractTest` |
| Delete | Deja de contar | `deleteTest` |
| Undelete | Vuelve a contar | `undeleteTest` |
| Subscription sin Contract | Sin errores ni logs | `subscriptionWithoutContractTest` |
| 200 inserts / 200 deletes | 200 / 0, dentro de los límites | `bulkInsertTest`, `bulkDeleteTest` |
| Vence por tiempo, sin que nadie la edite | El trigger no se entera; el Batch lo corrige | `expiredByTimeTest` |
| Número incorrecto (backfill) | El Batch lo corrige | `fixWrongCountTest` |
| 200 Contracts en una tanda | Los 200 corregidos | `bulkRecountTest` |
| El Scheduler se programa y lanza el Batch | Cron `0 0 2 * * ?` + 1 `AsyncApexJob` | `scheduleNightlyJobTest` |
| El job real ya existe con el mismo nombre | El test usa `JOB_NAME + ' (Test)'` | `scheduleNightlyJobTest` |
| Falla el update de un Contract | `Error_Log__c`, el resto se guarda | Sin test (ver sección 10) |

---

## 7. Preguntas probables del Code Review

**1. ¿Por qué no usaste un Roll-Up Summary?**
Porque solo existen en relaciones Master-Detail, y `SBQQ__Contract__c` es un Lookup del paquete de CPQ que no podemos cambiar. Además, un Roll-Up no puede filtrar por "hoy", y "activa" depende de la fecha. Por eso lo calculamos con Apex.

**2. ¿Por qué after y no before?**
Porque lo que cambiamos es otro registro, el Contract, y eso necesita un DML. Además, la query de recuento tiene que ver el cambio ya guardado: en before insert la Subscription todavía no tiene Id, y en before delete la query todavía la vería.

**3. ¿Por qué recontar todo en vez de sumar o restar 1?**
Porque un contador incremental se desfasa para siempre con el primer error, con una carga de datos o con una Subscription que cambia de Contract. Recontar siempre da el número correcto con los datos que hay. Cuesta lo mismo: 1 query y 1 update por transacción.

**4. ¿Por qué hace falta un Batch si ya tenés un trigger?**
Porque una Subscription puede empezar o vencer sin que nadie la edite: es el calendario el que avanza, como en el DEV #1. El trigger solo corre cuando alguien guarda algo. El Batch recuenta todas las noches a las 2:00 con el mismo método que el trigger.

**5. ¿Cómo manejás los Amendments?**
Lo probamos en el org: CPQ no modifica la Subscription original, crea una nueva por la diferencia (+100, −10) apuntando a la original. Contamos una vez cada original cuya suma vigente sea mayor a 0. En la demo da 1, no 3, y si un Amendment la baja a 0, deja de contar.

**6. ¿Qué pasa si una Subscription se cambia de Contract?**
En el update comparamos el Contract nuevo con el viejo (`Trigger.oldMap`) y agregamos **los dos** al mismo Set. Uno pierde una Subscription y el otro la gana, con la misma query y el mismo update. Lo prueba `moveToAnotherContractTest`.

**7. ¿Cómo evitás procesar de más en un update?**
`hasRelevantChange` compara con `Trigger.oldMap` solo los campos que pueden cambiar el conteo. Si cambia, por ejemplo, el precio, no se hace ninguna query. Y aunque se recalcule, si el número no cambió no se hace update.

**8. ¿Está bulkificado? ¿Cuántas queries y DML usa?**
Sí. Por transacción: **1 SOQL** (Contracts + subquery de Subscriptions) y **como máximo 1 DML** (más 1 insert de logs si algo falla), sean 1 o 200 Subscriptions. Lo prueban `bulkInsertTest` y `bulkDeleteTest` con 200 registros.

**9. ¿Puede haber recursión?**
No. Nuestro trigger actualiza Contract, no Subscription, y no tenemos trigger propio en Contract. Si un trigger de CPQ sobre Contract tocara Subscriptions, el recuento daría el mismo número y no haría update, así que la cadena se corta sola.

**10. ¿Qué pasa si falla el update de un Contract? ¿Se cae el contracting de CPQ?**
No. Usamos `Database.update( lista, false )`: los demás Contracts se guardan y el error queda en `Error_Log__c`. La transacción que nos llamó (por ejemplo, CPQ creando Subscriptions) sigue. El número se corrige esa noche con el Batch.

**11. ¿Por qué leés `SBQQ__StartDate__c` en la query pero comparás `SBQQ__SubscriptionStartDate__c` en el trigger?**
`SBQQ__StartDate__c` es una fórmula ("fecha propia o la del Contract"): sirve para el recuento, pero en `Trigger.new` las fórmulas no están recalculadas. Para detectar un cambio comparamos el campo real que alguien puede editar.

**12. ¿Por qué no mirás si el Contract está Activated?**
Fue un supuesto confirmado: el requirement habla de Subscriptions activas, no de Contracts activos, y activar el Contract es parte del DEV #3. Si lo miráramos, haría falta un trigger en Contract y el DEV #3 ya va a trabajar sobre ese objeto.

**13. ¿Cómo completaste el número de los Contracts que ya existían?**
Corriendo el Batch una vez a mano después del deploy (backfill), con el mismo código que corre de noche. Por eso el Batch recorre todos los Contracts y no solo los que tienen Subscriptions.

---

## 8. Cómo se prueba en la demo

### A. El número en el Contract
1. Abrir el **Contract 00000108**. **Tiene que verse:** *Active Subscriptions* = **1**, debajo de Contract Term, de solo lectura.
2. Related list **Subscriptions**: SUB-0000011 (125), SUB-0000012 (+100, inicio 01/04/2027) y SUB-0000013 (−10, inicio 01/07/2027). Explicar: los Amendments son una sola Subscription con cantidad cambiada, y además todavía no empezaron.

### B. El trigger en vivo
1. Abrir **SUB-0000010** (Contract 00000107, que muestra **1**) y completar **Terminated Date = hoy**. Guardar.
2. Volver al Contract 00000107 y refrescar. **Tiene que verse:** **0**.
3. Borrar el Terminated Date y guardar → el Contract vuelve a **1**.
4. *(Opcional)* Borrar la Subscription → 0. Recuperarla desde la Papelera → 1.

### C. El Amendment de la demo (Contract Change Use Cases)
1. En un Contract nuevo con Monthly Named Users × 125 → **Amend** → inicio a los 6 meses, cantidad 225 → Ordered.
2. Esperar unos segundos (contracting asíncrono). **Tiene que verse:** una Subscription nueva de +100, y el Contract sigue en **1**.

### D. El job nocturno
1. **Setup → Scheduled Jobs:** *Active Subscriptions Recount - Nightly*, próxima ejecución a las 2:00.
2. Para mostrarlo sin esperar: **Developer Console → Execute Anonymous**:
   ```apex
   Database.executeBatch( new ActiveSubscriptionRecountBatch() );
   ```
   Y mostrarlo **Completed** en **Setup → Apex Jobs**. Tab **Error Logs** vacía.

### Evidencia real en el org (02/10/2026)

| Prueba | Resultado |
|---|---|
| Amendments +100 / −10 sobre el Contract 00000108 (Q-00080, Q-00081 → Orders 00000121, 00000122) | SUB-0000012 (+100) y SUB-0000013 (−10), las dos apuntando a SUB-0000011 |
| Backfill (Batch a mano) | 00000100 = 2, 00000101 = 2, 00000102 = 1, 00000103 = 2, 00000104 = 1, 00000105 = 1, 00000107 = 1, **00000108 = 1** (3 registros) |
| Job programado | *Active Subscriptions Recount - Nightly*, `0 0 2 * * ?`, WAITING (próxima: 03/10/2026 2:00 America/Los_Angeles) |

---

## 9. Tests, cobertura y Build Tracker

### Tests del DEV #4 (23, todos pasan)

**`ActiveSubscriptionCounterTest`** (setup: Account, Product, Contract de 12 meses desde hoy)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `activeSubscriptionCountsTest` | Positivo | — | Inserta 1 Subscription sin fechas propias | Contract = 1 |
| `futureSubscriptionNotCountedTest` | Negativo | Inicio = mañana | Inserta | Contract = 0 |
| `endDateBoundaryTest` | Negativo + borde | Fin = ayer y fin = hoy | Inserta las 2 | Contract = 1 (solo la de hoy) |
| `terminatedDateBoundaryTest` | Negativo + borde | Terminada hoy y terminada mañana | Inserta las 2 | Contract = 1 (solo la de mañana) |
| `evergreenContractTest` | Positivo | Contract sin plazo (sin fin) | Inserta 1 | Contract = 1 |
| `amendmentRevisionsCountOnceTest` | Positivo | Original 125 | Inserta revisiones +100 y −10 vigentes | Contract = 1 (no 3) |
| `fullCancellationNotCountedTest` | Negativo | Original 125 | Inserta revisión −125 vigente | Contract = 0 |
| `futureCancellationStillCountsTest` | Borde | Original 125 | Inserta revisión −125 desde mañana | Contract = 1 |
| `emptySetSkipsQueryTest` | Negativo | — | Llama al recuento con Set vacío | 0 queries |
| `unchangedCountSkipsUpdateTest` | Negativo | 1 Subscription (Contract ya en 1) | Llama al recuento | 0 DML y sigue en 1 |

**`SubscriptionTriggerHandlerTest`** (setup: Account, Product, Contract A de 12 meses y B de 24)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `insertTest` | Positivo | — | Inserta 2 en A y 1 en B en un solo insert | A = 2, B = 1 |
| `updateRelevantFieldTest` | Positivo | 1 en A | Update TerminatedDate = hoy | A = 0 |
| `updateIrrelevantFieldTest` | Negativo | 1 en A, Contract forzado a 99 | Update del precio | A sigue en 99 (no recalculó) |
| `moveToAnotherContractTest` | Positivo | 1 en A | Cambia el Contract a B | A = 0, B = 1 |
| `deleteTest` | Positivo | 2 en A | Borra 1 | A = 1 |
| `undeleteTest` | Positivo | 1 en A, borrada | Undelete | A = 1 |
| `subscriptionWithoutContractTest` | Negativo | — | Inserta 1 sin Contract | A = 0 y 0 Error Logs |
| `bulkInsertTest` | Bulk | — | Inserta 200 en A | A = 200 |
| `bulkDeleteTest` | Bulk | 200 en A | Las borra | A = 0 |

**`ActiveSubscriptionRecountBatchTest`** (setup: Account, Product)

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `expiredByTimeTest` | Positivo | 1 Subscription (= 1). Mueve el Contract al pasado sin tocar la Subscription | Corre el Batch | Antes del Batch sigue en 1 (el trigger no se entera); después = 0 |
| `fixWrongCountTest` | Positivo | 1 Subscription, Contract forzado a 7 | Corre el Batch | = 1 y 0 Error Logs |
| `bulkRecountTest` | Bulk | 200 Contracts sin Subscriptions con 5 | Corre el Batch | Los 200 en 0 |

**`ActiveSubscriptionRecountSchedulerTest`**

| Test | Tipo | Prepara | Hace | Verifica (assert) |
|---|---|---|---|---|
| `scheduleNightlyJobTest` | Positivo | Nombre de job de test | `System.schedule` + `stopTest` | Cron `0 0 2 * * ?` y 1 Batch lanzado |

### Cobertura (corrida del 02/10/2026, todos los tests locales)

**53 métodos de test, 53 pasan.** El resumen de Salesforce dice "59" porque cuenta como un resultado más el `@testSetup` de cada una de las 6 clases que lo tienen. **Cobertura del org: 98%.**

| Clase / Trigger | Líneas cubiertas | Cobertura | Sin cubrir |
|---|---|---|---|
| `SubscriptionTrigger` | 8/8 | 100% | — |
| `SubscriptionTriggerHandler` | 35/35 | 100% | — |
| `ActiveSubscriptionCounter` | 48/50 | 96% | Líneas 151-152: arman el Error Log cuando **falla** el update de un Contract. Con datos normales de test no se puede hacer fallar ese update (mismo caso que `QuoteExpirationBatch` en el DEV #1). |
| `ActiveSubscriptionRecountBatch` | 8/8 | 100% | — |
| `ActiveSubscriptionRecountScheduler` | 2/2 | 100% | — |

### Build Tracker

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| SubscriptionTrigger | SubscriptionTriggerHandlerTest | 02/10/2026 | 100% |
| SubscriptionTriggerHandler | SubscriptionTriggerHandlerTest | 02/10/2026 | 100% |
| ActiveSubscriptionCounter | ActiveSubscriptionCounterTest (+ SubscriptionTriggerHandlerTest, ActiveSubscriptionRecountBatchTest) | 02/10/2026 | 96% |
| ActiveSubscriptionRecountBatch | ActiveSubscriptionRecountBatchTest | 02/10/2026 | 100% |
| ActiveSubscriptionRecountScheduler | ActiveSubscriptionRecountSchedulerTest | 02/10/2026 | 100% |

---

## 10. Limitaciones conocidas y pendientes de QA

1. **Rama de error sin cubrir** (líneas 151-152 de `ActiveSubscriptionCounter`), ver sección 9.
2. **El número puede estar desactualizado hasta las 2:00** cuando una Subscription empieza o vence por fecha, o cuando cambian las fechas del Contract. Es el costo de no tener un trigger en Contract: se corrige cada noche.
3. **Convivencia con CPQ en vivo:** los Amendments de prueba se hicieron **antes** de deployar el trigger (el número vino del backfill). Falta ver el trigger corriendo dentro del contracting de CPQ → **QA-DEV4-01**.
4. **Baja total por Amendment (a 0):** no se probó en el org si CPQ completa `SBQQ__TerminatedDate__c` → **QA-DEV4-02**. El código funciona en los dos casos.
5. **Hora del job:** 2:00 en la zona del usuario que lo programó (America/Los_Angeles). Si ese usuario se desactiva, el job deja de correr.
6. **Sharing:** depende de que Subscription y Contract sigan en Public Read/Write.
7. **Lección de deploy:** no desplegar la carpeta `classes` entera. `ErrorLogUtil` y las clases del DEV #1 las usa el job programado, y Salesforce no deja redeployarlas mientras el job está pendiente. Hay que desplegar solo los archivos cambiados.

Detalle en [`docs/qa-pending.md`](../qa-pending.md).
