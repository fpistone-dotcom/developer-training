# DEV #5 — Barra de progreso en la Quote · Resumen para el Code Review

> **Estado:** terminado, deployado y probado en el org (05/10/2026). Componente visible en *Training Quote Page* para los dos perfiles. Primer Quote Document del org generado sobre Q-00096 (5/5).

---

## 1. Qué pide el requirement

> "As a Sales User, I would like to be able to see a User-friendly UI on the Quote record that shows my current progress in the Quoting process. Specifically, I would like the following tasks to either have a green checkmark or red 'X': Quote Lines Added, Quote Approved, Quote Document Created, Opportunity Closed Won, Quote Ordered."

**En 2 líneas:** en la página de la Quote, un componente visual con los 5 pasos del proceso de cotización. Cada paso muestra un check verde si está hecho o una X roja si no.

| Parte | Qué significa | Dato que usamos | Dónde se cubre |
|---|---|---|---|
| (A) "Quote Lines Added" | La Quote tiene al menos un producto | `SBQQ__LineItemCount__c > 0` (Roll-Up Summary de CPQ) | `QuoteProgressController.buildSteps` |
| (B) "Quote Approved" | La Quote pasó la aprobación | `SBQQ__Status__c` en {Approved, Presented, Accepted} | `buildSteps` + `APPROVED_STATUS_SET` |
| (C) "Quote Document Created" | Se generó y guardó el PDF | Existe un `SBQQ__QuoteDocument__c` con `SBQQ__Quote__c` = esta Quote | Subquery de `getProgressSteps` |
| (D) "Opportunity Closed Won" | Se ganó la venta | `SBQQ__Opportunity2__r.IsWon` | `buildSteps` |
| (E) "Quote Ordered" | Se generó la Order | `SBQQ__Ordered__c` | `buildSteps` |
| (F) "User-friendly UI ... green checkmark or red X" | Componente en la record page | `isDone` de cada paso → ícono | LWC `quoteProgress` en *Training Quote Page* |

---

## 2. Diseño elegido

### Piezas

| Componente | Tipo | Rol |
|---|---|---|
| `QuoteProgressController` | Apex Class (`with sharing`, nueva) | Un método `@AuraEnabled getProgressSteps( quoteId )`: 1 SOQL, 0 DML. Calcula los 5 pasos y los devuelve en orden. **Toda la regla de negocio está acá.** |
| `QuoteProgressController.ProgressStep` | Clase interna (2 campos) | Un paso: `label` y `isDone`. |
| `quoteProgress` | Lightning Web Component (nuevo): `.html`, `.js`, `.js-meta.xml` | **Solo dibuja.** Llama a Apex al abrirse y con el botón ⟳. |
| `Training_Quote_Page` | FlexiPage (IC, **autorizado**) | Se agregó el componente arriba de la columna derecha. Es la página por defecto de la Quote para todo el org. |
| `Quote_Progress_Access` | Permission Set (IC, **autorizado**, nuevo) | Acceso a la clase Apex. Asignado a sh.dsales y frandev. |
| `TestDataFactory` | Test utility | Se sumaron `buildQuoteLines` y `buildQuoteDocument`. |
| `QuoteProgressControllerTest` | Test Class (nueva) | 12 tests, 100% de cobertura. |

### Qué es un LWC y cómo se conecta todo (para alguien que nunca vio uno)

Un **Lightning Web Component** es una pieza de pantalla hecha a medida que se pone en una página de Lightning, igual que los componentes estándar (Details, Related Lists). **Corre en el navegador** del usuario, no en el servidor. Es una carpeta con archivos del mismo nombre:

| Archivo | Qué es | En nuestro componente |
|---|---|---|
| `quoteProgress.js-meta.xml` | La **configuración**: dónde se puede usar el componente | `isExposed = true` (aparece en el App Builder), target `lightning__RecordPage` y objeto `SBQQ__Quote__c` (solo en páginas de Quote) |
| `quoteProgress.js` | La **lógica del navegador** | Recibe el `recordId`, llama a Apex, guarda la respuesta en `steps` y le agrega ícono y color a cada paso |
| `quoteProgress.html` | El **template**: qué se dibuja | Una `lightning-card` con un renglón por paso (`lightning-icon` + texto), el contador "3 of 5" y el botón ⟳ |
| `QuoteProgressController.cls` | **Apex en el servidor** | Hace la query y decide qué pasos están hechos |

**Cómo se hablan:**
- **`.js-meta.xml` ↔ página:** le dice al Lightning App Builder que el componente existe y en qué páginas se puede poner.
- **`.js` ↔ Apex:** `import getProgressSteps from '@salesforce/apex/QuoteProgressController.getProgressSteps';` convierte el método Apex en una función de JavaScript. Para que se pueda importar, el método tiene que ser `public static` y `@AuraEnabled`.
- **`.js` ↔ `.html`:** el HTML lee las propiedades del JS entre llaves (`{steps}`, `{progressSummary}`, `{errorMessage}`). Cuando el JS cambia una propiedad, **el HTML se vuelve a dibujar solo**. El botón llama al JS con `onclick={handleRefresh}`.
- **Página ↔ `.js`:** `@api recordId` es una propiedad que **Salesforce completa sola** con el Id de la Quote que se está mirando.

**El recorrido de una llamada** (se abre la página → se ven los ✅/❌):

```
Usuario abre la Quote
  └─► Salesforce crea el componente y le pone recordId = Id de la Quote
        └─► connectedCallback()  (el componente "aparece" en la página)
              └─► loadSteps(): isLoading = true  ──► el HTML muestra el spinner
                    └─► getProgressSteps({ quoteId: recordId })   (viaja al servidor)
                          └─► Apex: QuoteProgressController.getProgressSteps
                                ├─ 1 SOQL (Quote + IsWon de la Opportunity + documentos)
                                ├─ si no hay Quote → AuraHandledException
                                └─ buildSteps → lista de 5 ProgressStep  (vuelve como JSON)
                    ◄── .then(result): arma steps con ícono, color y texto
                    ◄── .catch(error): guarda error.body.message
                    ◄── .finally(): isLoading = false
              └─► el HTML se vuelve a dibujar: 5 renglones ✅/❌ + "3 of 5"
```

Cada llamada desde el LWC es una **transacción nueva en el servidor, con sus propios governor limits**, como si fuera un guardado aparte.

### Por qué así y qué descartamos (diseño general)

| Decisión | Por qué sí | Otras opciones y qué pasaría |
|---|---|---|
| **Apex controller + LWC** | Muestra 5 pasos **independientes** con ✅/❌ reales. La regla vive en Apex (testeable, con cobertura). Es lo que proponía el CLAUDE.md. | **Path + fórmulas:** el Path muestra **una** etapa a la vez, en secuencia, sobre un picklist: no puede mostrar 5 checks independientes (una Amendment está Ordered sin estar aprobada). **Solo fórmulas con `IMAGE()`:** "Document Created" no sale con fórmula (registros hijos por **lookup**, sin Roll-Up, el mismo problema del DEV #4). Habría que sumar un campo contador y un trigger en `SBQQ__QuoteDocument__c`, y tocar el layout. **Screen Flow embebido:** incómodo para íconos, y es IC. **LWC sin Apex (`getRecord`):** contar los documentos exige APIs más avanzadas y la lógica queda en JS, sin cobertura. **Aura:** tecnología anterior; para componentes nuevos se usa LWC. |
| **El LWC solo dibuja; la lógica está en Apex** | Si cambia la regla de "aprobada", se cambia en un lugar y lo cubren los tests de Apex. | **Devolver la Quote y decidir en JS:** el JS tendría que conocer los API names (incluido el nombre feo de la relación) y la regla quedaría sin tests de Apex ni cobertura. |
| **Llamada imperativa** (no `@wire`) | Se entiende como "llamar a una función". Refrescar es volver a llamarla. | **`@wire`:** corre sola cuando llega el `recordId`, pero exige `cacheable=true` (datos cacheados) y, para refrescar, `refreshApex`: otro concepto más. Con caché, ⟳ podría mostrar datos viejos. |
| **Sin `cacheable=true`** | Cada llamada va al servidor: siempre datos frescos. | **Con caché:** más rápido al reabrir, pero después de aprobar o generar un documento podría seguir mostrando ❌. |
| **Refresco: al abrir + botón ⟳** (opción A) | Lo más simple de explicar, y cubre todos los casos con un clic. | **Escuchar cambios del registro (`getRecord`):** se refresca sola en ediciones de la misma página, pero no detecta documentos ni cambios en la Opportunity: igual hace falta ⟳. **Polling** (consultar cada N segundos): llamadas al servidor sin parar, mala práctica. |
| **Arriba de la columna derecha** | Se ve sin hacer scroll y no empuja hacia abajo los Details. | **A lo ancho arriba de los Details:** ocupa mucho y empuja la información principal. **En el header:** solo admite ciertos componentes. |
| **Agregar el componente por metadata** (retrieve → XML → dry-run → deploy) | Queda versionado en git, reproducible en otro org, y se valida antes de aplicar. | **A mano en el App Builder:** igual de válido, pero el cambio no queda en el repo y no se puede revisar en el Code Review. |
| **Permission Set nuevo** (no editar el perfil) | Es aditivo, se asigna por usuario y sigue el patrón del DEV #4. | **Editar el perfil Direct Sales:** cambio más amplio sobre configuración del IC. **No dar acceso:** el usuario Direct Sales vería *"You do not have access to the Apex class named 'QuoteProgressController'"* en lugar de la barra. |

### Decisiones chicas del código: por qué sí y por qué no las otras

| Decisión | Por qué sí | Otras opciones y qué pasaría |
|---|---|---|
| **1 query con subquery** de documentos | Los 5 datos salen de una sola SOQL: campos de la Quote, `IsWon` del padre (lookup) e hijos (subquery). | **2 queries** (la Quote + un `COUNT()` de documentos): más legible, pero 2 SOQL. **Una query por paso:** 5 SOQL para lo mismo. |
| **El nombre `SBQQ__R00N70000001lX7YEAU__r`** | Es el nombre real de la relación documento → Quote (verificado con `sf sobject describe`). CPQ es un paquete viejo y nunca le puso un nombre legible. Lleva un comentario en el código. | No hay otro nombre posible para la subquery. La alternativa es la query aparte (ver arriba). |
| **`LIMIT 1` en la subquery** | Solo importa si existe **al menos uno**. | **Sin LIMIT:** traería todos los documentos (pueden ser muchos, uno por versión) sin necesidad. |
| **Filtrar documentos por `SBQQ__Quote__c`** | El documento es de **esta** Quote. | **Por `SBQQ__Opportunity__c`:** el documento de **otra** Quote de la misma Opportunity daría ✅ por error (lo prueba `documentOfOtherQuoteNotCountedTest`). |
| **`SBQQ__QuoteDocument__c` y no Files/Attachments** | Es el registro que crea CPQ al guardar el documento. CPQ guarda el PDF en un *Document* clásico (Id `015...`, verificado), no en Files de la Quote. | **Mirar `ContentDocumentLink` (Files):** no vería el PDF de CPQ y contaría cualquier archivo que alguien suba a mano. |
| **`SBQQ__DocumentStatus__c` descartado** | — | Está `null` en las 92 Quotes: sirve para el envío por email o e-signature, no para "documento creado". |
| **`SBQQ__LineItemCount__c > 0`** (sin chequear null) | Es un Roll-Up Summary que calcula CPQ: nunca es null (vale 0). 0 queries extra. | **Subquery de Quote Lines:** otra subquery para un dato que ya está calculado. **Chequear null:** código que nunca corre. |
| **`APPROVED_STATUS_SET` (Set constante)** | Solo preguntamos "¿está adentro?" (`contains`). Un lugar para los 3 valores, público para los tests. | **`List<String>`:** funciona, pero el Set es la colección natural para "pertenece". **`== 'Approved' \|\| == 'Presented' \|\| ...`:** más largo y más fácil de equivocar. **Solo `'Approved'`:** una Quote aprobada que pasa a Presented volvería a ❌. |
| **`IsWon` y no `StageName == 'Closed Won'`** | Lo calcula Salesforce según el tipo de etapa: no depende del texto. | **Por texto:** si se renombra la etapa, deja de funcionar sin avisar. |
| **`if ( SBQQ__Opportunity2__c != null )` antes de leer `IsWon`** | Explícito y seguro: sin Opportunity, el paso queda en ❌ sin errores (lo prueba `quoteWithoutOpportunityTest`). | **Leer `SBQQ__Opportunity2__r.IsWon` directo:** dependeríamos de cómo trata Apex un padre vacío. El `if` se lee mejor. |
| **Cada paso por separado** (no "si falta uno, los siguientes en rojo") | En el org los pasos **no** son secuenciales: las Amendments (Q-00080, Q-00094) están Ordered en Draft y con la Opportunity abierta. | **Barra secuencial:** mostraría mal esas Quotes, como si no estuvieran Ordered. |
| **Clase interna `ProgressStep` (label, isDone)** | Es la forma de mandarle al navegador una lista **ordenada** con estructura. `@AuraEnabled` en cada campo lo incluye en el JSON. | **`Map<String, Boolean>`:** el orden de los pasos quedaría a cargo del JS, y los textos serían a la vez claves y datos. **Devolver la Quote:** ver "el LWC solo dibuja". |
| **`AuraHandledException` si la Quote no existe** | Ver el apartado de abajo. | Ver el apartado de abajo. |
| **`with sharing`** | El usuario solo ve el progreso de Quotes que puede ver. | **`without sharing`:** el controller leería Quotes que el usuario no ve. |
| **Textos de los pasos como constantes `public`** | Los tests comparan contra la misma constante: si cambia el texto, no se rompen. | **Textos sueltos:** habría que repetirlos en los tests. **Custom Labels:** permiten traducir sin deploy, pero están fuera del curso y no se pidieron. |
| **Ícono y color calculados en el JS** (`iconName`, `iconVariant`) | Es **presentación**, no negocio: el HTML de LWC no admite ternarios en el template. | **Mandarlos desde Apex:** mezclaría pantalla con lógica de negocio en el controller. |

### `AuraHandledException` (fuera del curso, explicada)

- **Qué es:** una excepción de Apex pensada para los métodos `@AuraEnabled`. El texto que lleva **llega al navegador** y el LWC lo puede mostrar (`error.body.message`).
- **Por qué hace falta:** si un método `@AuraEnabled` tira una excepción común, Salesforce **oculta** el detalle al navegador (por seguridad) y el usuario ve un error genérico. Con `AuraHandledException`, el usuario ve *"The Quote was not found or you do not have access to it."*
- **`setMessage`:** en Apex, `getMessage()` de una `AuraHandledException` devuelve *"Script-thrown exception"* si no se llama a `setMessage`. Lo llamamos para que el test pueda verificar el texto exacto (`quoteNotFoundTest`).
- **Cuándo pasa:** la Quote fue borrada, o el usuario no la ve (`with sharing` → la query vuelve vacía).
- **Alternativas:** **devolver una lista vacía:** el LWC mostraría una card vacía sin explicar por qué (fallar en silencio, Módulo 3). **No chequear:** `quoteList[0]` tiraría `ListException` y el usuario vería un error técnico genérico.

### `SBQQ.TriggerControl.disable()` en `allStepsCompletedTest` (y por qué solo ahí)

- **Qué es:** un método del paquete CPQ que **apaga los triggers de CPQ** en la transacción. Los nuestros siguen corriendo. Ya lo usamos en el DEV #3 (2 tests bulk).
- **Qué pasó:** primero corrimos los 12 tests con CPQ prendido. Pasaron 11. `allStepsCompletedTest` falló **por validaciones de CPQ**, de a una:
  1. *"Opportunity must have a primary quote in order to create an order"*.
  2. Con la Quote como Primary, *"Required fields are missing: [PricebookEntryId]"*: al tildar `SBQQ__Ordered__c`, **CPQ intenta crear la Order real** con sus productos.
- **Por qué no armamos el Pricebook completo:** el test pasaría a depender de toda la cadena del Req #31 (generación de la Order de CPQ, nuestro `OrderTrigger` del DEV #2, el Flow 2, el contracting). Si mañana falla algo de esa cadena, se rompería el test del DEV #5 por algo que no tiene nada que ver. Esa cadena ya se probó en el org (DEV #2).
- **Por qué solo alrededor de ese `update`:** apagamos CPQ, tildamos `Ordered`, y lo volvemos a prender (`enable()`). El controller se ejecuta **con CPQ prendido**, igual que los otros 11 tests. Insertar Quote Lines y Quote Documents funcionó con CPQ prendido.
- **Por qué no hay test de "solo Ordered":** para eso habría que repetir `TriggerControl` en otro test, para un campo que el controller lee directo. Ese paso lo cubre `allStepsCompletedTest`, y en el org lo muestran Q-00094 y Q-00096.

---

## 3. Flujo paso a paso

### A) La lógica, sin código

1. El vendedor abre una Quote.
2. En la columna derecha aparece la card **Quote Progress**, que pregunta al servidor en qué estado está la Quote.
3. El servidor mira 5 cosas, **cada una por separado**:
   - ¿Tiene productos? (el contador de líneas que mantiene CPQ)
   - ¿Está aprobada? (Status Approved, o uno posterior: Presented o Accepted)
   - ¿Tiene un documento generado? (un Quote Document de **esta** Quote)
   - ¿La Opportunity se ganó?
   - ¿Se generó la Order? (el check Ordered)
4. Devuelve los 5 pasos en orden, cada uno con "hecho" o "no hecho".
5. La card muestra un check verde o una X roja por paso, y el resumen "N of 5".
6. Si el vendedor hace algo en otra pantalla (aprueba, genera el documento, cierra la Opportunity), vuelve a la Quote y toca **⟳**: se repite desde el paso 2.

**Ejemplo real (Q-00096):** tenía productos, estaba aprobada, la Opportunity ganada y la Quote Ordered, pero no tenía documento → **4 of 5**. Se generó el documento → ⟳ → **5 of 5**.

### B) El código en orden cronológico

1. **Usuario** abre la Quote → Salesforce carga **`Training_Quote_Page`** (org default de la Quote en escritorio).
2. La página incluye el componente **`quoteProgress`** (región `sidebar`, primero). Salesforce le pone **`recordId`** = Id de la Quote.
3. **`quoteProgress.js` → `connectedCallback()`** → **`loadSteps()`**: `isLoading = true` → **`quoteProgress.html`** muestra `lightning-spinner`.
4. `loadSteps()` llama a **`getProgressSteps({ quoteId: this.recordId })`** (import de `@salesforce/apex`). Viaja al servidor.
5. **Servidor → `QuoteProgressController.getProgressSteps( quoteId )`** (transacción nueva):
   - a. **1 SOQL:** `SBQQ__LineItemCount__c`, `SBQQ__Status__c`, `SBQQ__Ordered__c`, `SBQQ__Opportunity2__c`, `SBQQ__Opportunity2__r.IsWon` y la subquery `( SELECT Id FROM SBQQ__R00N70000001lX7YEAU__r LIMIT 1 )`.
   - b. Si la lista está vacía → arma una **`AuraHandledException`** con `QUOTE_NOT_FOUND_MESSAGE` (`setMessage`) y la lanza.
   - c. Si no → **`buildSteps( quote )`**: calcula `hasQuoteLines`, `isApproved` (`APPROVED_STATUS_SET.contains`), `hasDocument` (subquery no vacía), `isClosedWon` (con el `if` de la Opportunity) e `isOrdered`. Arma 5 **`ProgressStep`** en orden y los devuelve.
6. Salesforce convierte la lista en **JSON** y la manda al navegador.
7. **`quoteProgress.js` → `.then(result)`:** `result.map(...)` le agrega a cada paso `iconName` (`utility:success` / `utility:close`), `iconVariant` (`success` / `error`) e `iconText` (texto alternativo) → `this.steps = ...`.
   - **Si hubo error → `.catch(error)`:** `steps = []` y `errorMessage = error.body.message` (o un texto genérico).
   - **`.finally()`:** `isLoading = false`.
8. **`quoteProgress.html` se vuelve a dibujar solo:** `for:each={steps}` → un `<li>` por paso con `lightning-icon` + `{step.label}`. En el encabezado, el getter **`progressSummary`** ("3 of 5"), visible solo si `hasSteps`. Si hay error, `{errorMessage}` en rojo.
9. **Botón ⟳** (`lightning-button-icon`, `onclick={handleRefresh}`) → **`handleRefresh()`** → `loadSteps()` → se repite desde el paso 3.

---

## 4. Código explicado por bloques

### `QuoteProgressController`

**Bloque 1: constantes**
```apex
public static final String STEP_QUOTE_LINES = 'Quote Lines Added';
...
public static final Set<String> APPROVED_STATUS_SET = new Set<String>{ 'Approved', 'Presented', 'Accepted' };
public static final String QUOTE_NOT_FOUND_MESSAGE = 'The Quote was not found or you do not have access to it.';
```
- **Qué hace:** los textos de los pasos (tal cual el requirement), los estados que cuentan como aprobada y el mensaje de error.
- **Regla del training:** constantes `static final` en UPPER_CASE; colección con nombre en plural/tipo (`...StatusSet`) (**Módulo 1**). Públicas para que los tests usen las mismas.

**Bloque 2: clase interna `ProgressStep`**
```apex
public class ProgressStep {
    @AuraEnabled public String label;
    @AuraEnabled public Boolean isDone;
    public ProgressStep( String label, Boolean isDone ) { ... }
}
```
- **Qué hace:** representa un paso. `@AuraEnabled` en cada campo hace que viaje en el JSON.
- **Por qué así:** es la forma mínima de devolver datos con estructura al LWC. 2 campos tipados, un constructor. No es un "wrapper complejo".

**Bloque 3: `getProgressSteps` (la query)**
```apex
@AuraEnabled
public static List<ProgressStep> getProgressSteps( Id quoteId ) {
    List<SBQQ__Quote__c> quoteList = [
        SELECT Id, SBQQ__LineItemCount__c, SBQQ__Status__c, SBQQ__Ordered__c,
            SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.IsWon,
            ( SELECT Id FROM SBQQ__R00N70000001lX7YEAU__r LIMIT 1 )
        FROM SBQQ__Quote__c
        WHERE Id = :quoteId
    ];
```
- **Qué hace:** trae todo lo necesario en **1 SOQL**.
- **Regla del training:** relación lookup para datos del padre y subquery para los hijos; query de más de 100 caracteres con una cláusula por línea; WHERE para traer solo lo necesario (**Módulo 1 SOQL**). `public static` (**Módulo 1**). Una lista y no `SBQQ__Quote__c quote = [...]`, porque la asignación directa tira excepción si no hay filas.

**Bloque 4: Quote no encontrada**
```apex
if ( quoteList.isEmpty() ) {
    AuraHandledException notFoundException = new AuraHandledException( QUOTE_NOT_FOUND_MESSAGE );
    notFoundException.setMessage( QUOTE_NOT_FOUND_MESSAGE );
    throw notFoundException;
}
return buildSteps( quoteList[0] );
```
- **Qué hace:** error legible para el usuario (ver sección 2). Si no, delega en `buildSteps`.
- **Regla del training:** manejo de errores sin fallar en silencio (**Módulo 3**). `if` con llaves (**Módulo 1**).

**Bloque 5: `buildSteps` (la regla de negocio)**
```apex
Boolean hasQuoteLines = quote.SBQQ__LineItemCount__c > 0;
Boolean isApproved = APPROVED_STATUS_SET.contains( quote.SBQQ__Status__c );
Boolean hasDocument = !quote.SBQQ__R00N70000001lX7YEAU__r.isEmpty();
Boolean isClosedWon = false;
if ( quote.SBQQ__Opportunity2__c != null ) {
    isClosedWon = quote.SBQQ__Opportunity2__r.IsWon;
}
Boolean isOrdered = quote.SBQQ__Ordered__c;
List<ProgressStep> stepList = new List<ProgressStep>();
stepList.add( new ProgressStep( STEP_QUOTE_LINES, hasQuoteLines ) );
... // los 5 en el orden del requirement
return stepList;
```
- **Qué hace:** un `Boolean` con nombre descriptivo por paso (Req A a E) y la lista en orden.
- **Por qué así:** cada paso se lee en una línea. `private static` con la lógica (**Módulo 2**, mismo patrón que los handlers). El resultado de una subquery nunca es null (sin hijos es una lista vacía), por eso alcanza con `isEmpty()`.

### `quoteProgress.js`

| Bloque | Qué hace | Por qué así |
|---|---|---|
| `import { LightningElement, api } from 'lwc';` | Trae la clase base de todo LWC y el decorador `@api` | Obligatorio en todo LWC |
| `import getProgressSteps from '@salesforce/apex/...'` | Convierte el método Apex en una función JS | Es la forma estándar de llamar a Apex |
| `@api recordId;` | Salesforce lo completa con el Id de la Quote | Sin `@api`, Salesforce no le pasaría el Id |
| `steps`, `isLoading`, `errorMessage` | El estado que dibuja el HTML | Cuando cambian, el HTML se vuelve a dibujar solo |
| `connectedCallback()` | Llama a `loadSteps()` cuando el componente aparece | Es el "al abrir la página" |
| `handleRefresh()` | Llama a `loadSteps()` desde el botón | Opción A de refresco |
| `loadSteps()` | Llamada imperativa: `.then` / `.catch` / `.finally` | `.then` = salió bien, `.catch` = error (equivalente al try/catch de Apex), `.finally` = siempre (apaga el spinner) |
| `result.map(...)` | Agrega ícono, color y texto alternativo a cada paso | Presentación en JS; el template no admite ternarios |
| `get progressSummary()` | Calcula "N of 5" | Getter: se recalcula solo cuando cambian los pasos |
| `get hasSteps()` | Si hay pasos para mostrar | El template usa condiciones simples (`lwc:if`) |

### `quoteProgress.html`

- **`lightning-card`** con título e ícono: el "marco" estándar de Salesforce, igual a los componentes nativos.
- **`slot="actions"`**: zona derecha del encabezado, con el "N of 5" (solo si `hasSteps`) y el **`lightning-button-icon`** ⟳.
- **`lwc:if={isLoading}`** → `lightning-spinner`. **`lwc:if={errorMessage}`** → el mensaje en rojo (`slds-text-color_error`).
- **`for:each={steps}`** → un `<li>` por paso. LWC exige un **`key`** único por renglón: usamos `step.label`.
- **`lightning-icon`** con `variant` `success` (verde) o `error` (rojo) y **`alternative-text`** "Completed" / "Not completed", para lectores de pantalla (accesibilidad: el color solo no alcanza).
- Clases **SLDS** (`slds-media`, `slds-p-horizontal_medium`): el sistema de estilos propio de Salesforce. No es una librería externa: viene con la plataforma.

### `quoteProgress.js-meta.xml`
- `isExposed = true` + target `lightning__RecordPage` + objeto `SBQQ__Quote__c`: aparece en el App Builder solo para páginas de Quote. `masterLabel` "Quote Progress" es el nombre que se ve en la lista.

### `Training_Quote_Page` (lo agregado)
```xml
<itemInstances>
    <componentInstance>
        <componentName>quoteProgress</componentName>
        <identifier>c_quoteProgress</identifier>
    </componentInstance>
</itemInstances>
```
- Primer ítem de la región **`sidebar`** (columna derecha), antes de los Related List Quick Links. El archivo se trajo del org con `sf project retrieve start` (antes no estaba en el repo).

### `Quote_Progress_Access`
- `classAccesses` → `QuoteProgressController` habilitada. Sin permisos de objeto ni de campo: el usuario ya ve la Quote por su perfil.

### `TestDataFactory` (lo agregado)
- **`buildQuoteLines( quoteId, productId, n )`:** N Quote Lines sin insertar. Al insertarlas, CPQ recalcula `SBQQ__LineItemCount__c`.
- **`buildQuoteDocument( quoteId, opportunityId )`:** un Quote Document sin insertar (solo `SBQQ__Quote__c` es obligatorio, verificado con el describe).

---

## 5. Supuestos y decisiones

Confirmadas por Francisco (05/10/2026):

1. **Apex controller + LWC**, llamada **imperativa**.
2. **Lista ordenada** con la clase interna mínima `ProgressStep` (`label`, `isDone`).
3. **"Quote Approved" = Status Approved, Presented o Accepted** (supuesto): Presented y Accepted son estados **posteriores** a la aprobación en el ciclo de CPQ. Hoy ninguna Quote del org los usa.
4. **Fuentes:** `SBQQ__LineItemCount__c > 0`, `SBQQ__QuoteDocument__c` por `SBQQ__Quote__c`, `Opportunity.IsWon`, `SBQQ__Ordered__c`.
5. **1 query** con subquery (nombre de la relación comentado).
6. **Quote no encontrada → `AuraHandledException`**.
7. **Refresco:** al abrir + botón ⟳.
8. **Ubicación:** arriba de la columna derecha.
9. **`Training_Quote_Page` por metadata**, con dry-run. Verificado: es el **org default** de la Quote en escritorio (`actionOverrides` View, formFactor Large), la única FlexiPage de Quote del org, y las apps de ventas no tienen asignaciones por perfil para la Quote → la ven System Administrator y Direct Sales.
10. **Permission Set `Quote_Progress_Access`**, asignado a sh.dsales y frandev.
11. **Quote Document real sobre Q-00096**, generado con la API de CPQ (`SBQQ.ServiceRouter.save('SBQQ.QuoteDocumentAPI.Save', ...)`, lo mismo que *Generate Document → Save*). "Demo estrella" armada después del deploy (sección 8).
12. **Textos de la UI en inglés.**
13. **`SBQQ.TriggerControl.disable()`** solo si hacía falta y solo para armar datos: hizo falta en `allStepsCompletedTest` (sección 2).

**Otros supuestos:**
- **Los pasos son independientes**, no secuenciales (ver Q-00094 en la sección 8).
- **Cualquier documento cuenta**, aunque sea un borrador (template DRAFT). El requirement dice "Document Created", no "Final Document".
- **Las Quotes temporales de CPQ** (DEV #3) no afectan: el componente solo lee la Quote abierta, y la temporal vive unos segundos y nadie la abre.
- **Escritorio:** en celular (formFactor Small) la Quote usa la página por defecto del sistema, sin el componente (sección 10).

---

## 6. Edge cases

| Caso | Cómo se maneja | Test |
|---|---|---|
| Quote nueva (Draft, sin nada) | 5 ❌ | `newQuoteAllStepsPendingTest` |
| Todo completo | 5 ✅ | `allStepsCompletedTest` + Q-00096 en el org |
| Orden y textos de los pasos | Los del requirement | `stepsOrderAndLabelsTest` |
| Solo con líneas | Solo el paso 1 en ✅ | `quoteLinesAddedTest` |
| Solo con documento | Solo el paso 3 en ✅ | `quoteDocumentCreatedTest` |
| Documento de **otra** Quote de la misma Opportunity | No cuenta | `documentOfOtherQuoteNotCountedTest` |
| Solo Opportunity Closed Won | Solo el paso 4 en ✅ | `opportunityClosedWonTest` |
| Quote sin Opportunity | Paso 4 en ❌, sin NullPointerException | `quoteWithoutOpportunityTest` |
| Status Approved / Presented / Accepted | Paso 2 en ✅ | `approvedStatusesTest` |
| Status Draft / In Review / Denied / Rejected | Paso 2 en ❌ | `notApprovedStatusesTest` |
| Eficiencia | 1 sola SOQL | `singleQueryTest` |
| Quote borrada o sin acceso | `AuraHandledException` con mensaje → texto rojo en la card | `quoteNotFoundTest` |
| Amendment: Ordered pero no aprobada ni Closed Won | Se muestra tal cual (2/5): pasos independientes | En el org: Q-00094 |
| Quote aprobada (bloqueada) a la que se le genera un documento | Funciona: el documento es un registro hijo | En el org: Q-00096 |
| Varios documentos (una versión por cada vez que se genera) | ✅ (`LIMIT 1`: alcanza con uno) | Por diseño |
| Usuario sin acceso a la clase Apex | Error en la card. Resuelto con el permission set | Permission set asignado (QA-DEV5-01) |
| Cambios en otra pantalla (aprobación, documento, Opportunity) | Botón ⟳ o recargar la página | Demo (sección 8) |
| Quote temporal de CPQ (DEV #3) | No aplica: nadie la abre y se borra en segundos | — |

---

## 7. Preguntas probables del Code Review

**1. ¿Qué es un LWC y por qué lo usaste?**
Es un componente de pantalla hecho a medida que corre en el navegador y se pone en una página de Lightning. Lo usamos porque el requirement pide 5 checks independientes con ✅/❌, y ni el Path ni las fórmulas pueden mostrar "Document Created" (son registros hijos por lookup, sin Roll-Up).

**2. ¿Cómo se comunica el LWC con Apex?**
El método Apex es `public static` y `@AuraEnabled`. En el JS se importa con `@salesforce/apex/Clase.metodo` y se llama como una función que devuelve una Promise. Cada llamada es una transacción nueva en el servidor, con sus propios governor limits, y la respuesta vuelve como JSON.

**3. ¿Por qué la lógica está en Apex y no en el JavaScript?**
Porque así se testea con test classes de Apex y suma a la cobertura del 85%. Además el JS no necesita conocer API names ni el nombre raro de la relación. Si cambia la regla, se cambia en un solo lugar.

**4. ¿Cuántas queries hace y por qué no hay test bulk de 200?**
Una sola SOQL, con un lookup al padre (`IsWon`) y una subquery a los hijos (documentos). Lo verifica `singleQueryTest`. No hay bulk porque el método recibe **una** Quote: una página muestra una Quote, no hay loop de registros.

**5. ¿Qué es `SBQQ__R00N70000001lX7YEAU__r`?**
Es el nombre de la relación entre el Quote Document y la Quote, generado por Salesforce cuando CPQ creó el lookup sin nombre legible (paquete viejo). Lo verificamos con `sf sobject describe`. Está comentado en el código.

**6. ¿Por qué Presented y Accepted cuentan como aprobada?**
Son estados posteriores a la aprobación en el ciclo de CPQ. Si una Quote aprobada pasa a Presented (se le mostró al cliente), sería raro que el check se vuelva rojo. Es un supuesto documentado; hoy ninguna Quote del org los usa.

**7. ¿Qué pasa si el usuario aprueba la Quote o genera un documento? ¿Se actualiza solo?**
Esos cambios pasan en otras pantallas, y Lightning puede reusar la página vieja. El componente carga al abrirse y tiene un botón ⟳ que vuelve a pedir los datos. No usamos caché (`cacheable=true`), así que ⟳ siempre trae datos frescos.

**8. ¿Por qué `AuraHandledException`?**
Porque si un método `@AuraEnabled` tira una excepción común, Salesforce oculta el detalle y el usuario ve un error genérico. Con `AuraHandledException` el mensaje llega al navegador y el LWC lo muestra. `setMessage` es para que el test pueda leer el texto.

**9. ¿Por qué usaste `SBQQ.TriggerControl.disable()` en un test?**
Solo para armar el dato de una Quote Ordered en `allStepsCompletedTest`. Al tildar Ordered, CPQ intenta crear la Order real y exige Primary, Pricebook y PricebookEntry, y eso arrastra toda la cadena del #31. Lo apagamos solo durante ese update y lo prendemos enseguida: el controller corre con CPQ prendido.

**10. ¿Por qué los pasos se evalúan por separado y no en secuencia?**
Porque en el org no son secuenciales: las Amendments están Ordered sin estar aprobadas ni Closed Won (Q-00094). Una barra secuencial las mostraría mal. Cada paso dice la verdad sobre su propio dato.

**11. ¿Por qué `IsWon` y no `StageName = 'Closed Won'`?**
`IsWon` lo calcula Salesforce según el tipo de etapa: no depende del texto. Si alguien renombra la etapa, la comparación por texto dejaría de funcionar sin avisar.

**12. ¿Cómo lo agregaste a la página? ¿Tocaste el IC?**
Sí, con autorización. Traje `Training_Quote_Page` con `sf project retrieve start`, agregué el componente en el XML, validé con `--dry-run` y desplegué. Así queda versionado en git. También verifiqué que sea la página activa para los dos perfiles.

**13. ¿Por qué hizo falta un permission set?**
Porque para llamar a una clase Apex desde un LWC, el usuario necesita acceso a esa clase. El admin lo tiene por defecto; Direct Sales no. Sin el permission set, el vendedor vería un error de acceso en lugar de la barra.

**14. ¿El documento de otra Quote cuenta?**
No. Filtramos por `SBQQ__Quote__c` (el documento de **esta** Quote), no por `SBQQ__Opportunity__c`. Si no, una Opportunity con dos Quotes mostraría ✅ en la que no tiene documento. Lo prueba `documentOfOtherQuoteNotCountedTest`.

---

## 8. Cómo se prueba en la demo

### A. Quotes en distintos estados (sin crear nada)

Abrir cada una y mostrar la card *Quote Progress* (columna derecha):

| Quote | Qué es | Barra | Qué decir |
|---|---|---|---|
| **Q-00079** | Draft, sin productos, Opportunity en Prospecting | ❌❌❌❌❌ **0 of 5** | "Una Quote recién empezada." |
| **Q-00108** | Renewal Quote del DEV #3, 1 línea | ✅❌❌❌❌ **1 of 5** | "La generó CPQ con nuestro Batch del DEV #3." |
| **Q-00074** | Aprobada por el Manager, sin productos | ❌✅❌❌❌ **1 of 5** | "Prueba de aprobaciones del IC." |
| **Q-00094** | Amendment: 1 línea, Ordered, Draft, Opportunity en Prospecting | ✅❌❌❌✅ **2 of 5** | "Los pasos son independientes: CPQ ordena las Amendments sin aprobación ni Closed Won." |
| **Q-00096** | Venta completa + documento generado | ✅✅✅✅✅ **5 of 5** | "El camino completo." |

Verificado el 05/10/2026 llamando al controller para cada una: los 5 resultados coinciden.

### B. Guion de la "demo estrella" (una Quote nueva de 0/5 a 5/5, en vivo)

**Antes de la demo (5 minutos):**
- Loguearse como **frandev**. La validación del Req #30 aplica al perfil Direct Sales; con admin el Closed Won no se bloquea por perfil, pero igual exige una Quote aprobada.
- Crear una Opportunity **"DEV5 Demo - Quote Progress"**, Account *Burlington Textiles Corp of America*, Stage **Prospecting**, Close Date dentro de 30 días.
- Tener a mano la Quote **Q-00096** (plan B) y *Setup → Apex Jobs* en otra pestaña.

| # | Qué hacés en la UI | Barra esperada | Qué decir (conexión con los otros DEV) | Si falla o tarda |
|---|---|---|---|---|
| 1 | En la Opportunity → **New Quote** (botón de CPQ). Dejar **Primary** tildado, **Payment Terms = Net 30** y **sin descuento**. Save. Abrir la Quote. | ❌❌❌❌❌ **0 of 5** | "La barra carga sola al abrir la Quote: el LWC llama a Apex en el `connectedCallback`. Una sola query." | **Payment Terms tiene que ser Net 30:** si queda vacío, la Quote entra al proceso con el paso de Finance y no se aprueba sola (Q-00078). |
| 2 | **Edit Lines** → *Add Products* → **Monthly Named Users** → Quantity **10** → **Save** (volver a la Quote). | ✅❌❌❌❌ **1 of 5** (tocar **⟳**) | "El paso 1 sale del Roll-Up de CPQ que cuenta las líneas: no gasta queries extra. Usamos un producto de suscripción para que al final CPQ cree un Contract (DEV #4)." | Si sigue en ❌, esperar 2 s y ⟳ (Lightning puede tardar en volver del editor). **Esperar 5–10 s antes del paso 5:** CPQ calcula los precios en un Queueable. Si se ordena antes, falla con *"Order Products must have a Unit Price"*. |
| 3 | **Submit for Approval** (el mismo botón de las pruebas del IC). | ✅✅❌❌❌ **2 of 5** (⟳) | "Net 30 y sin descuento → entra en **Auto_Approval** (IC) y se aprueba sola. Miren **Expiration Date = hoy + 30** (04/11/2026): lo puso el trigger del **DEV #1** cuando el Status pasó a Approved. Ahora la Quote está bloqueada por la aprobación." | Si queda **In Review**, entró en `Quote_Approval_V2`: revisar Payment Terms y descuento. Plan B: aprobarla como frandev desde *Items to Approve*. |
| 4 | **Generate Document** → template **SmartBytes Quote - FINAL** (la aprobación lo dejó elegido) → **Save** → volver a la Quote. | ✅✅✅❌❌ **3 of 5** (⟳) | "CPQ crea un registro *Quote Document* de **esta** Quote. Funciona aunque la Quote esté bloqueada, porque el documento es un registro hijo." | La generación es **asíncrona** (`QueueableQuoteDocumentService`, unos segundos). Si sigue en ❌: esperar 5–10 s y ⟳. Si no aparece, ver *Apex Jobs*. Plan B: Q-00096. |
| 5 | Ir a la **Opportunity** → Stage **Closed Won** → Save. Volver a la Quote. | ✅✅✅✅✅ **5 of 5** (⟳) | "La validación del **Req #30** deja pasar porque la Primary Quote está aprobada. El **Flow 1** (IC) marcó la Quote como **Ordered** → CPQ creó la Order → nuestro **DEV #2** la activó cuando el calculador terminó → el **Flow 2** la contrata → CPQ crea Contract + Subscription. Los dos últimos checks se ponen verdes juntos." | Si aparece Closed Won ✅ pero Ordered ❌: esperar unos segundos y ⟳ (el Flow corre en el mismo save; lo que tarda es CPQ). Si el save falla con *"Unit Price"*, esperar y repetir (riesgo del paso 2). |
| 6 *(opcional)* | En la Opportunity → related list **Orders** → la Order nueva. Después, Account → **Contracts**. | — | "Order **Activated** (DEV #2). El Contract aparece unos segundos después (contracting asíncrono) con **Active Subscriptions = 1** (DEV #4). Nace en Draft: al activarlo arranca el DEV #3." | El Contract tarda unos segundos: refrescar. |

**Frase para cerrar (20 segundos):** "El componente no guarda nada: cada vez que se abre o se toca ⟳, le pregunta a Apex en qué estado está la Quote. Una sola query mira 5 datos reales de CPQ, cada uno por separado, y el LWC solo pinta un check verde o una X roja."

### C. Error controlado (opcional, si preguntan por `AuraHandledException`)
Mostrar el test `quoteNotFoundTest`. En la UI no se puede abrir una Quote borrada (la página misma da error), por eso este caso se prueba con el test.

### Evidencia real en el org (05/10/2026)

| Prueba | Resultado |
|---|---|
| Dry-run de los 6 componentes | Validado, 12/12 tests |
| Deploy real | `0Affj00000TZxm8CAD`, Succeeded, 12/12 tests |
| Permission set | Asignado a sh.dsales@firstchair-training.com y frandev@firstchair.com |
| Controller sobre Quotes reales | Q-00079 0/5 · Q-00108 1/5 · Q-00074 1/5 · Q-00094 2/5 · Q-00096 4/5 |
| Quote Document | "Q-00096 - Proposal" (PDF, template FINAL, Document `015fj00000An1ObAAJ`), job `QueueableQuoteDocumentService` **Completed**, 0 errores → Q-00096 **5/5** |
| Página activa | `Training_Quote_Page` = org default de View (Large) para `SBQQ__Quote__c` |

---

## 9. Tests, cobertura y Build Tracker

### C) Tests del DEV #5 (12, todos pasan)

**`QuoteProgressControllerTest`** (setup: Account, Opportunity en Prospecting, Product2)

| Test | Tipo | Prepara | Verifica (assert) |
|---|---|---|---|
| `newQuoteAllStepsPendingTest` | Negativo | Quote Draft en Opportunity abierta | 5 pasos, todos ❌ |
| `allStepsCompletedTest` | Positivo | Opportunity Closed Won, Quote Approved + 1 línea + documento + Ordered (CPQ apagado solo en ese update) | 5 ✅ |
| `stepsOrderAndLabelsTest` | Positivo | Quote Draft | Orden y textos del requirement |
| `quoteLinesAddedTest` | Borde | Quote con 2 líneas | Solo el paso 1 ✅ |
| `quoteDocumentCreatedTest` | Borde | Quote con documento | Solo el paso 3 ✅ |
| `documentOfOtherQuoteNotCountedTest` | Negativo | Documento en otra Quote de la misma Opportunity | Paso 3 ❌ |
| `opportunityClosedWonTest` | Borde | Quote de una Opportunity Closed Won | Solo el paso 4 ✅ |
| `quoteWithoutOpportunityTest` | Borde | Quote sin Opportunity | Paso 4 ❌, sin excepción |
| `approvedStatusesTest` | Positivo | Approved, Presented, Accepted | Paso 2 ✅ en las 3 |
| `notApprovedStatusesTest` | Negativo | Draft, In Review, Denied, Rejected | Paso 2 ❌ en las 4 |
| `singleQueryTest` | Eficiencia | Quote Draft | `Limits.getQueries() == 1` |
| `quoteNotFoundTest` | Negativo | Quote insertada y borrada | `AuraHandledException` con `QUOTE_NOT_FOUND_MESSAGE` |

**Notas de testing:**
- `Limits.getQueries()` se lee entre `Test.startTest()` y `Test.stopTest()`: `startTest` arranca un juego de límites nuevo, así que cuenta **solo** las queries del controller.
- Las Quote Lines y los Quote Documents se insertaron **con CPQ prendido**.
- El LWC no tiene tests propios: Jest (tests de JavaScript) no está en el training y no cuenta para la cobertura de Apex. Se probó en el org (sección 8).

### Cobertura (corrida del 05/10/2026, 16:59 UTC, todos los tests locales)

**83 métodos de test, 83 pasan.** Salesforce informa 92 porque cuenta el `@testSetup` de cada una de las 9 clases que lo tienen. **Cobertura del org: 96%.**

| Clase | Líneas cubiertas | Cobertura | Sin cubrir |
|---|---|---|---|
| `QuoteProgressController` | 27/27 | **100%** | — |

### D) Cobertura TOTAL del org: los 5 DEV superan el 85%

| DEV | Clase / Trigger | Cobertura | Sin cubrir y por qué |
|---|---|---|---|
| #2 | `OrderTrigger` | 100% | — |
| #2 | `OrderTriggerHandler` | 100% | — |
| #2 | `OrderActivationQueueable` | 100% | — |
| #2 | `ErrorLogUtil` | 100% | — |
| #1 | `QuoteTrigger` | 100% | — |
| #1 / #3 | `QuoteTriggerHandler` | 91% | 205-206 (falla de un email individual), 209 y 211-213 (el `catch` del envío). En un test no se puede hacer fallar `Messaging.sendEmail`. |
| #1 | `QuoteExpirationBatch` | 93% | 112-113 (Error Log cuando un recall falla): no se puede forzar con datos de test. |
| #1 | `QuoteExpirationScheduler` | 100% | — |
| #4 | `SubscriptionTrigger` | 100% | — |
| #4 | `SubscriptionTriggerHandler` | 100% | — |
| #4 | `ActiveSubscriptionCounter` | 96% | 151-152 (Error Log cuando falla el update de un Contract). |
| #4 | `ActiveSubscriptionRecountBatch` | 100% | — |
| #4 | `ActiveSubscriptionRecountScheduler` | 100% | — |
| #3 | `ContractTrigger` | 100% | — |
| #3 | `ContractTriggerHandler` | 100% | — |
| #3 | `RenewalQuoteBatch` | 91% | 123, 139, 156-157 (ramas de error y de seguridad: updates fallidos, sin Opportunity en Prospecting). |
| #3 | `RenewalQuoteScheduler` | 100% | — |
| #5 | `QuoteProgressController` | 100% | — |

**Mínimo por clase: 91%. Org: 96%.** Todas superan el 85%. Lo único sin cubrir son **ramas de error** que no se pueden provocar con datos de test (un DML, un recall o un email que falla), y todas registran en `Error_Log__c`.

### Build Tracker (DEV #5)

| Componente | Test Class | Última corrida | Cobertura |
|---|---|---|---|
| QuoteProgressController | QuoteProgressControllerTest | 05/10/2026 | 100% |
| quoteProgress (LWC) | — (probado en el org; Jest fuera del training) | 05/10/2026 | N/A |

### E) Build Tracker completo
Ver [`docs/BUILD-TRACKER.md`](../BUILD-TRACKER.md) (los 5 DEV, listo para copiar).

---

## 10. Limitaciones conocidas y pendientes de QA

1. **No se refresca solo** con cambios hechos en otras pantallas: hay que tocar ⟳ o recargar (decisión 7).
2. **Solo escritorio:** en la app móvil (formFactor Small) la Quote usa la página por defecto del sistema, que no tiene el componente. No se pidió.
3. **Supuesto de "Approved":** Presented y Accepted cuentan como aprobada. Si el negocio quisiera solo Approved, es cambiar el Set.
4. **Cualquier documento cuenta**, también uno generado con el template DRAFT.
5. **Dependencia de CPQ:** el nombre de la relación `SBQQ__R00N70000001lX7YEAU__r` y el Roll-Up `SBQQ__LineItemCount__c` son del paquete. Si una versión futura los cambiara, habría que revisar la query.
6. **Textos fijos en inglés** (en Apex y en el HTML): cambiarlos requiere un deploy. Para traducirlos se usarían Custom Labels (fuera del curso).
7. **Sin tests de JavaScript (Jest):** el LWC se probó en el org.

Pendientes de QA (detalle en [`docs/qa-pending.md`](../qa-pending.md)):
- **QA-DEV5-01:** ver la barra como **sh.dsales** (Direct Sales) en la UI.
- **QA-DEV5-02:** la "demo estrella" completa desde la UI (Quote Line Editor, Submit, botón Generate Document, Closed Won), anotando la Quote creada.
