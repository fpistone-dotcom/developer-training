# DEV #5 · Paso a paso para la defensa (barra de progreso en la Quote)

> **Para qué sirve este documento:** es la guía para **mostrar y explicar** el DEV #5 en el Code Review, en el orden en que se ejecuta. El detalle completo (diseño, decisiones chicas, 14 preguntas, demo estrella, Build Tracker) está en [`docs/code-review/DEV5.md`](../code-review/DEV5.md). Acá no se repite, se referencia. Los patrones que se repiten en todos los DEV están en [`00-patrones-base.md`](00-patrones-base.md).
>
> **Este DEV es distinto a los otros cuatro:** no hay trigger, no hay DML y no hay async. Hay una pantalla (LWC) que corre en el navegador y una clase Apex que solo **lee**. Por eso la sección 0 explica LWC desde cero.
>
> Los números de línea son del commit `9b24af8` (07/10/2026). Si el código cambia, revisarlos.

---

## 0. LWC desde cero (lo que tenés que saber antes de la tabla)

### 0.1 Qué es un LWC

Un **Lightning Web Component** es una pieza de pantalla hecha a medida que se arrastra a una página de Lightning, igual que los componentes estándar (Details, Related Lists, Path). La diferencia clave con todo lo que hicimos en los DEV #1 a #4:

| | Trigger / Batch (DEV #1–#4) | LWC (DEV #5) |
|---|---|---|
| **Dónde corre** | En el **servidor** de Salesforce | En el **navegador** del usuario (JavaScript) |
| **Cuándo corre** | Cuando alguien **guarda** un registro, o a una hora | Cuando alguien **abre** la página (o toca un botón) |
| **Qué hace** | Cambia datos | **Muestra** datos (este no cambia nada) |
| **Cómo llega a la base** | Directo (SOQL/DML) | **No puede** hacer SOQL: le pide a una clase Apex que la haga |

### 0.2 Los 3 archivos del componente

Un LWC es una **carpeta** con archivos del mismo nombre: [`force-app/main/default/lwc/quoteProgress/`](../../force-app/main/default/lwc/quoteProgress/).

| Archivo | Qué es (analogía) | Qué tiene el nuestro |
|---|---|---|
| [`quoteProgress.js-meta.xml`](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js-meta.xml) | **La ficha técnica**: le dice a Salesforce que el componente existe y dónde se puede usar | `isExposed = true` (línea 6: aparece en el App Builder), `masterLabel` "Quote Progress" (línea 7: el nombre en la lista), target `lightning__RecordPage` (línea 9: va en páginas de registro) y objeto `SBQQ__Quote__c` (línea 15: **solo** en páginas de Quote) |
| [`quoteProgress.js`](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js) | **El cerebro del navegador** | Recibe el `recordId`, llama a Apex, guarda la respuesta en `steps` y le agrega ícono y color a cada paso |
| [`quoteProgress.html`](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html) | **El dibujo** (template) | Una `lightning-card` con un renglón por paso (ícono + texto), el contador "N of 5" y el botón ⟳ |

Y del lado del servidor, una cuarta pieza que no es parte del componente: [`QuoteProgressController.cls`](../../force-app/main/default/classes/QuoteProgressController.cls) (Apex, la query y la regla de negocio).

**Cómo se hablan entre sí:**
- **`.html` lee del `.js`** con llaves: `{steps}`, `{progressSummary}`, `{errorMessage}`. Cuando el JS cambia una de esas propiedades, **el HTML se vuelve a dibujar solo** (eso se llama *reactividad*: no hay que "refrescar" a mano la pantalla).
- **`.html` llama al `.js`** con eventos: `onclick={handleRefresh}` en el botón.
- **`.js` llama a Apex** con un `import` especial (ver 0.4).

### 0.3 Cómo recibe el `recordId`

[quoteProgress.js:11](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L11): `@api recordId;`

- `@api` marca la propiedad como **pública**: alguien de afuera del componente la puede completar.
- Cuando el componente está en una **record page**, Salesforce busca una propiedad pública que se llame **exactamente** `recordId` y le pone el Id del registro que se está mirando (la Quote). No escribimos ningún código para eso: es una convención de la plataforma.
- Sin `@api`, o con otro nombre (`quoteId`), Salesforce no le pasaría nada y la llamada a Apex iría con `null`.

### 0.4 Cómo llama al controller Apex

**Del lado Apex** ([QuoteProgressController.cls:65-66](../../force-app/main/default/classes/QuoteProgressController.cls#L65-L66)):
```apex
@AuraEnabled
public static List<ProgressStep> getProgressSteps( Id quoteId )
```
Para que un LWC pueda llamar a un método Apex, el método tiene que ser **`public static`** y tener **`@AuraEnabled`** (la anotación que dice "este método se puede llamar desde componentes Lightning"). La clase tiene que ser accesible para el usuario (ver permission set, sección 3).

**Del lado JS** ([quoteProgress.js:3](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L3)):
```js
import getProgressSteps from '@salesforce/apex/QuoteProgressController.getProgressSteps';
```
Ese `import` convierte el método Apex en una **función de JavaScript**. Se llama pasándole un objeto con los parámetros **por nombre** (`{ quoteId: this.recordId }`: el nombre tiene que coincidir con el parámetro de Apex) y devuelve una **Promise**: una "promesa" de que la respuesta va a llegar más tarde, porque viaja por internet al servidor.

- `.then(result => ...)` = "cuando llegue bien, hacé esto" (como el bloque normal de un `try`).
- `.catch(error => ...)` = "si falló, hacé esto" (como el `catch` de Apex).
- `.finally(() => ...)` = "siempre, al final" (como el `finally` de Apex, Módulo 3).

**Cada llamada es una transacción nueva en el servidor**, con sus propios governor limits, como si fuera un guardado aparte.

### 0.5 `@wire` vs imperativo, y `cacheable`

Hay **dos formas** de llamar a Apex desde un LWC:

| | **Imperativa** (la que usamos) | **`@wire`** (la descartada) |
|---|---|---|
| **Cómo es** | Llamás la función cuando querés: `getProgressSteps({...}).then(...)` | Decorás una propiedad y Salesforce la llama **solo** cuando llega el `recordId` |
| **Requisito en Apex** | Ninguno extra | El método **tiene que** tener `@AuraEnabled(cacheable=true)` |
| **Refrescar** | Volver a llamar la función (el botón ⟳ hace eso) | Hay que usar `refreshApex`, otro concepto más |
| **Datos** | Siempre van al servidor → frescos | Puede devolver lo que guardó el **caché** del navegador |

**`cacheable=true`** le dice a Salesforce "este método solo lee, podés guardar la respuesta y reusarla". Es más rápido, pero en nuestro caso es un problema: aprobás la Quote en otra pantalla, volvés, y la barra podría seguir mostrando ❌ porque usa la respuesta vieja. **Nuestro método no tiene `cacheable`** a propósito (ApexDoc en [QuoteProgressController.cls:60-61](../../force-app/main/default/classes/QuoteProgressController.cls#L60-L61)). Alternativas y "qué pasaría": [DEV5.md §2](../code-review/DEV5.md#por-qué-así-y-qué-descartamos-diseño-general).

### 0.6 La única SOQL y de dónde sale cada paso

[QuoteProgressController.cls:72-78](../../force-app/main/default/classes/QuoteProgressController.cls#L72-L78):
```apex
SELECT Id, SBQQ__LineItemCount__c, SBQQ__Status__c, SBQQ__Ordered__c,
    SBQQ__Opportunity2__c, SBQQ__Opportunity2__r.IsWon,              ← dato del PADRE (lookup)
    ( SELECT Id FROM SBQQ__R00N70000001lX7YEAU__r LIMIT 1 )           ← HIJOS (subquery)
FROM SBQQ__Quote__c
WHERE Id = :quoteId
```

| # | Paso | Objeto | Campo / dato | Línea donde se decide | Por qué ese y no otro (resumen) |
|---|---|---|---|---|---|
| 1 | Quote Lines Added | `SBQQ__Quote__c` | `SBQQ__LineItemCount__c > 0` (Roll-Up Summary de CPQ que cuenta las Quote Lines) | [:100](../../force-app/main/default/classes/QuoteProgressController.cls#L100) | Ya está calculado: 0 queries extra. Nunca es null (vale 0). |
| 2 | Quote Approved | `SBQQ__Quote__c` | `SBQQ__Status__c` ∈ {Approved, Presented, Accepted} | [:103](../../force-app/main/default/classes/QuoteProgressController.cls#L103) + Set en [:34](../../force-app/main/default/classes/QuoteProgressController.cls#L34) | Presented y Accepted vienen **después** de aprobar (supuesto). |
| 3 | Quote Document Created | `SBQQ__QuoteDocument__c` (hijo, lookup `SBQQ__Quote__c`) | La subquery trae al menos 1 | [:106](../../force-app/main/default/classes/QuoteProgressController.cls#L106) | Es el registro que crea CPQ al guardar el PDF. Filtrado por **esta** Quote, no por la Opportunity. |
| 4 | Opportunity Closed Won | `Opportunity` (padre, lookup `SBQQ__Opportunity2__c`) | `IsWon` | [:110-113](../../force-app/main/default/classes/QuoteProgressController.cls#L110-L113) | `IsWon` no depende del texto de la etapa. El `if` evita el NullPointer si no hay Opportunity. |
| 5 | Quote Ordered | `SBQQ__Quote__c` | `SBQQ__Ordered__c` | [:116](../../force-app/main/default/classes/QuoteProgressController.cls#L116) | El check que tilda el Flow 1 del IC al pasar a Closed Won. |

**`SBQQ__R00N70000001lX7YEAU__r`** es el nombre de la relación Quote Document → Quote. Es feo porque CPQ es un paquete viejo y nunca le puso nombre legible; lo verificamos con `sf sobject describe` y está comentado en [:68-71](../../force-app/main/default/classes/QuoteProgressController.cls#L68-L71). `LIMIT 1` porque solo importa si existe **al menos uno**.

### 0.7 La clase interna `ProgressStep`

[QuoteProgressController.cls:43-56](../../force-app/main/default/classes/QuoteProgressController.cls#L43-L56): una clase **dentro** de la clase, con 2 campos (`label`, `isDone`) y un constructor.

- **Para qué:** Apex le tiene que mandar al navegador **una lista ordenada de 5 cosas con estructura**. Salesforce convierte esa lista en **JSON** automáticamente: `[{"label":"Quote Lines Added","isDone":true}, ...]`.
- **`@AuraEnabled` en cada campo** ([:44-45](../../force-app/main/default/classes/QuoteProgressController.cls#L44-L45)): sin eso, el campo **no viaja** en el JSON y el JS recibiría objetos vacíos.
- **Por qué no un `Map<String, Boolean>`:** el orden de los pasos quedaría a cargo del JS y los textos serían a la vez claves y datos. Con la lista, Apex decide el orden.
- No es un "wrapper complejo" (lo que el training dice evitar): 2 campos tipados y un constructor.

### 0.8 `AuraHandledException`

[QuoteProgressController.cls:81-87](../../force-app/main/default/classes/QuoteProgressController.cls#L81-L87).

- **Problema:** si un método `@AuraEnabled` tira una excepción común, Salesforce **esconde** el detalle al navegador (por seguridad) y el usuario ve un error genérico.
- **Solución:** `AuraHandledException` es la excepción "para mostrar". Su mensaje **sí** llega al navegador, en `error.body.message`, y el `.catch` del JS lo pone en rojo en la card ([quoteProgress.js:44-50](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L44-L50) → [quoteProgress.html:23-25](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L23-L25)).
- **Cuándo pasa:** la Quote fue borrada, o el usuario no la puede ver (la clase es `with sharing`, entonces la query vuelve vacía).
- **`setMessage`** ([:85](../../force-app/main/default/classes/QuoteProgressController.cls#L85)): sin él, `getMessage()` en Apex devuelve *"Script-thrown exception"* y el test no podría verificar el texto.
- Por qué no "devolver lista vacía": fallar en silencio (Módulo 3). Detalle: [DEV5.md §2](../code-review/DEV5.md#aurahandledexception-fuera-del-curso-explicada).

### 0.9 El botón de refresh

[quoteProgress.html:8-13](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L8-L13) → `onclick={handleRefresh}` → [quoteProgress.js:24-26](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L24-L26) → `loadSteps()`, **la misma función** que corre al abrir. Por qué hace falta: cuando aprobás, generás el documento o cerrás la Opportunity, eso pasa en **otra pantalla**; Lightning puede reusar la página vieja de la Quote sin volver a crear el componente. Como no hay caché, ⟳ siempre trae datos frescos.

### 0.10 Por qué los pasos son independientes (no secuenciales)

[QuoteProgressController.cls:92-125](../../force-app/main/default/classes/QuoteProgressController.cls#L92-L125): cada paso es un `Boolean` propio, calculado sin mirar los otros. **No** hay "si falta el 2, el 3 al 5 van en rojo".

**Por qué:** en el org los pasos **no siempre** ocurren en orden. Una **Amendment** (Q-00094) está **Ordered** sin estar aprobada y con la Opportunity en Prospecting: CPQ ordena las Amendments por su cuenta. Una barra secuencial la mostraría 1/5 (mentira: está ordenada); la nuestra la muestra ✅❌❌❌✅ **2/5**, que es la verdad. Cada check dice la verdad sobre **su** dato. Por eso tampoco usamos el **Path** estándar: muestra una etapa a la vez, en secuencia.

### 0.11 Por qué no hay trigger en este DEV

Un trigger corre cuando alguien **guarda** algo y sirve para **cambiar** datos. Acá:
- **No hay que cambiar nada:** el requirement pide **ver** el progreso. Los 5 datos ya existen en el org (los mantienen CPQ, el Approval Process y los Flows).
- **No hay que guardar el resultado:** se calcula **al abrir la página**, siempre fresco. Guardarlo en un campo (con trigger) implicaría mantenerlo al día desde **4 objetos distintos** (Quote, Quote Line, Quote Document, Opportunity): 4 triggers para algo que una query resuelve en el momento.
- Resultado: **0 DML, 0 triggers, 1 SOQL por apertura.** Ninguna automatización nueva que pueda romper la cadena del #31.

---

## 1. Requirement en 2 líneas (palabras de vendedor)

- "Cuando abro una Quote quiero ver **de un vistazo** en qué paso estoy: si ya tiene productos, si está aprobada, si generé el PDF, si gané la Opportunity y si ya salió la Order."
- "Verde si está hecho, rojo si falta; sin tener que abrir 4 pantallas para averiguarlo."

Texto original y tabla de partes (A)…(F): [DEV5.md §1](../code-review/DEV5.md#1-qué-pide-el-requirement).

---

## 2. Flujo lógico (sin código)

1. El vendedor abre una Quote → la página incluye la card **Quote Progress** (columna derecha).
2. La card corre en el navegador y **no puede leer la base**: le pregunta a una clase Apex por el Id de la Quote.
3. Apex hace **una sola query** que trae los 5 datos: 3 de la Quote, 1 de la Opportunity padre y "¿hay algún documento?" de los hijos.
4. Evalúa cada paso **por separado** (no son secuenciales) y devuelve una lista ordenada de 5 pasos con "hecho / no hecho".
5. El navegador pone un ✅ verde o una ❌ roja por paso y el resumen "N of 5".
6. Si la Quote no existe o no la puede ver, Apex manda un error **legible** y la card lo muestra en rojo.
7. No se guarda nada: si algo cambió en otra pantalla, el botón ⟳ vuelve a preguntar.

---

## 3. Cronología demo → código

### Vista general

```
NAVEGADOR (quoteProgress)                         SERVIDOR (QuoteProgressController)
─────────────────────────                         ──────────────────────────────────
Abro la Quote → Training_Quote_Page
  └─ crea quoteProgress, recordId = Id Quote
       └─ connectedCallback() → loadSteps()
            isLoading = true → spinner
            getProgressSteps({quoteId}) ───────►  getProgressSteps( quoteId )   (transacción nueva)
                                                    ├─ 1 SOQL (Quote + IsWon + subquery docs)
                                                    ├─ vacía → AuraHandledException
                                                    └─ buildSteps → 5 ProgressStep
            .then(result) ◄──────── JSON ──────────┘
              map → iconName / iconVariant / iconText
            .catch(error) → errorMessage
            .finally → isLoading = false
       └─ el HTML se redibuja: 5 renglones ✅/❌ + "N of 5"
Toco ⟳ → handleRefresh() → loadSteps() → (se repite)
```

### Antes de abrir: cómo llegó el componente a la página (configuración, una vez)

| # | Qué hice | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| A | Deploy del LWC | Salesforce registra el componente en el App Builder | [quoteProgress.js-meta.xml:6-18](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js-meta.xml#L6-L18) | `isExposed`, label, target `lightning__RecordPage`, solo `SBQQ__Quote__c` | metadata |
| B | Agregar a la página **por metadata**: `sf project retrieve start` de `Training_Quote_Page` → edité el XML → `deploy --dry-run` → deploy | La página tiene el componente como **primer ítem** de la columna derecha | [Training_Quote_Page.flexipage-meta.xml:89-95](../../force-app/main/default/flexipages/Training_Quote_Page.flexipage-meta.xml#L89-L95) (región `sidebar`, [:106](../../force-app/main/default/flexipages/Training_Quote_Page.flexipage-meta.xml#L106)) | `componentName = quoteProgress`, antes de los Related List Quick Links. Es la **org default** de la Quote en escritorio → la ven los dos perfiles | metadata (IC autorizado) |
| C | Permission set **`Quote_Progress_Access`** asignado a sh.dsales y frandev | Da permiso para ejecutar la clase Apex | [Quote_Progress_Access.permissionset-meta.xml:3-6](../../force-app/main/default/permissionsets/Quote_Progress_Access.permissionset-meta.xml#L3-L6) | Solo `classAccesses` de `QuoteProgressController`. Sin permisos de objeto/campo: la Quote ya la ven por perfil. Sin esto, Direct Sales vería *"You do not have access to the Apex class…"* | metadata (IC autorizado) |

**Por qué metadata y no a mano en el App Builder:** queda versionado en git, se valida con dry-run y se puede revisar en el Code Review. **Por qué permission set y no editar el perfil:** es aditivo, por usuario, y no toca el IC de Direct Sales (mismo patrón que el DEV #4). Detalle: [DEV5.md §2](../code-review/DEV5.md#por-qué-así-y-qué-descartamos-diseño-general).

### La ejecución: desde que abro la Quote hasta los 5 ✅/❌

Ejemplo: **Q-00094** (Amendment) → ✅❌❌❌✅ **2 of 5**.

| # | Qué hago / veo en la UI | Qué se dispara | Archivo:línea | Qué hace esa parte | Contexto |
|---|---|---|---|---|---|
| 1 | Abro la Quote Q-00094 | Salesforce carga `Training_Quote_Page` y crea el componente | [Training_Quote_Page.flexipage-meta.xml:92](../../force-app/main/default/flexipages/Training_Quote_Page.flexipage-meta.xml#L92) | La página dice "acá va `quoteProgress`" | navegador |
| 2 | (no se ve) | Salesforce completa `recordId` | [quoteProgress.js:11](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L11) | `@api recordId` = Id de Q-00094, sin código nuestro | navegador |
| 3 | (no se ve) | El componente "aparece" en la página | [quoteProgress.js:18-20](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L18-L20) | `connectedCallback()` = el "al abrir" del LWC → `loadSteps()` | navegador |
| 4 | Veo el **spinner** un instante | `isLoading = true` → el HTML se redibuja | [quoteProgress.js:30-31](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L30-L31) → [quoteProgress.html:18-20](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L18-L20) | Limpia el error anterior y muestra `lightning-spinner` | navegador |
| 5 | (no se ve) | **Llamada imperativa** a Apex | [quoteProgress.js:33](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L33) (import en [:3](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L3)) | `getProgressSteps({ quoteId: this.recordId })` → viaja al servidor, devuelve una Promise | navegador → servidor |
| 6 | (no se ve) | Entra al método `@AuraEnabled` | [QuoteProgressController.cls:65-66](../../force-app/main/default/classes/QuoteProgressController.cls#L65-L66) | `public static`, **sin** `cacheable` → siempre datos frescos. Transacción **nueva**, sus propios limits | servidor (síncrono) |
| 7 | (no se ve) | **La única SOQL** | [QuoteProgressController.cls:72-78](../../force-app/main/default/classes/QuoteProgressController.cls#L72-L78) | Quote + `SBQQ__Opportunity2__r.IsWon` (padre) + subquery de documentos `LIMIT 1` (hijos). Como `with sharing`, solo si el usuario la ve | servidor |
| 8 | (no se ve) | ¿Existe? | [QuoteProgressController.cls:81-87](../../force-app/main/default/classes/QuoteProgressController.cls#L81-L87) | Lista vacía → `AuraHandledException` con `setMessage`. Q-00094 existe → sigue | servidor |
| 9 | (no se ve) | → `buildSteps` | [QuoteProgressController.cls:89](../../force-app/main/default/classes/QuoteProgressController.cls#L89) → [:98](../../force-app/main/default/classes/QuoteProgressController.cls#L98) | `private static` con la regla de negocio | servidor |
| 10 | (no se ve) | Paso 1 | [:100](../../force-app/main/default/classes/QuoteProgressController.cls#L100) | `LineItemCount = 1 > 0` → **true** | servidor |
| 11 | (no se ve) | Paso 2 | [:103](../../force-app/main/default/classes/QuoteProgressController.cls#L103) | Status Draft ∉ Set → **false** | servidor |
| 12 | (no se ve) | Paso 3 | [:106](../../force-app/main/default/classes/QuoteProgressController.cls#L106) | Subquery vacía → **false** | servidor |
| 13 | (no se ve) | Paso 4 | [:110-113](../../force-app/main/default/classes/QuoteProgressController.cls#L110-L113) | Tiene Opportunity → `IsWon` (Prospecting) → **false** | servidor |
| 14 | (no se ve) | Paso 5 | [:116](../../force-app/main/default/classes/QuoteProgressController.cls#L116) | `SBQQ__Ordered__c` → **true** (los pasos son independientes) | servidor |
| 15 | (no se ve) | Arma la lista en orden | [:118-124](../../force-app/main/default/classes/QuoteProgressController.cls#L118-L124) | 5 `new ProgressStep( CONSTANTE, Boolean )` en el orden del requirement | servidor |
| 16 | (no se ve) | Salesforce convierte a **JSON** | [:44-45](../../force-app/main/default/classes/QuoteProgressController.cls#L44-L45) | Viajan `label` e `isDone` por tener `@AuraEnabled` | servidor → navegador |
| 17 | (no se ve) | `.then(result)` | [quoteProgress.js:34-43](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L34-L43) | `map` agrega `iconName` (`utility:success`/`utility:close`), `iconVariant` (`success`/`error`) e `iconText`. Presentación en JS porque el template no admite ternarios | navegador |
| 18 | (no se ve) | `.finally()` | [quoteProgress.js:51-53](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L51-L53) | `isLoading = false` → se va el spinner | navegador |
| 19 | Veo **5 renglones**: ✅ Quote Lines Added, ❌ Quote Approved, ❌ Quote Document Created, ❌ Opportunity Closed Won, ✅ Quote Ordered | El HTML se redibuja solo (reactividad) | [quoteProgress.html:28-43](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L28-L43) | `for:each={steps}` → un `<li>` por paso con `key={step.label}` (LWC exige una clave única), `lightning-icon` verde/rojo con `alternative-text` (accesibilidad) | navegador |
| 20 | Veo **"2 of 5"** arriba a la derecha | Getters | [quoteProgress.html:5-7](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L5-L7) ← [quoteProgress.js:57-64](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L57-L64) | `progressSummary` cuenta los `isDone`; `hasSteps` lo oculta si no hay pasos | navegador |
| 21 | Toco **⟳** (por ej. después de aprobar en otra pantalla) | `onclick` | [quoteProgress.html:8-13](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L8-L13) → [quoteProgress.js:24-26](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L24-L26) | `handleRefresh()` → `loadSteps()` → **se repite desde el paso 4** | navegador |

### Camino de error (Quote borrada o sin acceso)

| # | Qué veo | Qué se dispara | Archivo:línea | Qué hace | Contexto |
|---|---|---|---|---|---|
| E1 | — | Query vacía → `throw` | [QuoteProgressController.cls:81-87](../../force-app/main/default/classes/QuoteProgressController.cls#L81-L87) | `AuraHandledException( QUOTE_NOT_FOUND_MESSAGE )` ([:36](../../force-app/main/default/classes/QuoteProgressController.cls#L36)) | servidor |
| E2 | — | `.catch(error)` | [quoteProgress.js:44-50](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L44-L50) | `steps = []`, `errorMessage = error.body.message` (o texto genérico si no viene) | navegador |
| E3 | Texto rojo: *"The Quote was not found or you do not have access to it."* | Redibujo | [quoteProgress.html:23-25](../../force-app/main/default/lwc/quoteProgress/quoteProgress.html#L23-L25) | `slds-text-color_error`; sin "N of 5" porque `hasSteps = false` | navegador |

En la UI no se puede abrir una Quote borrada (la página misma falla), por eso este camino se muestra con el test `quoteNotFoundTest`.

---

## 4. Qué decir (guion mientras muestro el código)

1. "El requirement pide **ver** el progreso, no cambiar nada: por eso no hay trigger ni DML. Los 5 datos ya existen en el org; los calculo **al abrir la página**, siempre frescos."
2. "Es un **Lightning Web Component**: 3 archivos. El `js-meta.xml` dice que solo se puede poner en páginas de Quote, el `js` es la lógica del navegador y el `html` el dibujo. Salesforce le pasa solo el Id de la Quote por `@api recordId`."
3. "El componente no puede hacer SOQL: llama a `QuoteProgressController.getProgressSteps`, un método `public static @AuraEnabled`, de forma **imperativa** y **sin caché**, para que el botón ⟳ siempre traiga datos frescos."
4. "En Apex hay **una sola query**: los campos de la Quote, el `IsWon` de la Opportunity por el lookup y una subquery de Quote Documents con `LIMIT 1`. Cada paso es un `Boolean` independiente, porque en el org los pasos no son secuenciales: esta Amendment está Ordered sin estar aprobada."
5. "Devuelvo una lista ordenada de `ProgressStep`, una clase de 2 campos con `@AuraEnabled` para que viajen en el JSON. Toda la regla está en Apex: está testeada al 100% y el JS solo elige el ícono."
6. "Si la Quote no existe o el usuario no la ve, tiro una `AuraHandledException`: es la única excepción cuyo mensaje llega al navegador, así que el vendedor ve un texto claro en vez de un error genérico."

---

## 5. Decisiones y alternativas (resumen)

- **Apex controller + LWC** en lugar de Path (secuencial, una etapa a la vez), fórmulas con `IMAGE()` (no pueden ver los documentos hijos por lookup) o Screen Flow; la **lógica en Apex** y el LWC solo dibuja.
- **Llamada imperativa sin `cacheable`** + refresco al abrir y con ⟳, en lugar de `@wire` + `refreshApex` (caché → datos viejos) o polling.
- **1 SOQL con subquery**, pasos **independientes**, componente agregado **por metadata** y acceso con un **permission set** nuevo en lugar de editar el perfil.

Detalle con "por qué sí / por qué no / qué pasaría", incluidas las decisiones chicas (Set vs List, `IsWon` vs `StageName`, filtrar por Quote y no por Opportunity, `with sharing`, constantes públicas, ícono en JS): [DEV5.md §2](../code-review/DEV5.md#2-diseño-elegido).

### Dónde aparecen los patrones base en este DEV

Explicación general de cada patrón: [00-patrones-base.md](00-patrones-base.md).

| Patrón | Dónde aparece en el DEV #5 |
|---|---|
| **Un trigger por objeto → handler** | **No aplica:** no hay trigger (ver §0.11). El equivalente es la separación **LWC (pantalla) → controller (lógica)**: método de entrada `public static @AuraEnabled` ([:65-66](../../force-app/main/default/classes/QuoteProgressController.cls#L65-L66)) → lógica `private static` ([:98](../../force-app/main/default/classes/QuoteProgressController.cls#L98)), igual que entrada del handler → método privado. |
| **Bulkificación** | No hay loop de registros: el método recibe **una** Quote (una página = una Quote). Igual: 1 SOQL fuera de cualquier loop ([:72-78](../../force-app/main/default/classes/QuoteProgressController.cls#L72-L78)), verificado con `singleQueryTest`. |
| **WHERE / traer solo lo necesario** | `WHERE Id = :quoteId` ([:77](../../force-app/main/default/classes/QuoteProgressController.cls#L77)) y `LIMIT 1` en la subquery ([:75](../../force-app/main/default/classes/QuoteProgressController.cls#L75)). |
| **Lookup al padre + subquery a los hijos** | `SBQQ__Opportunity2__r.IsWon` ([:74](../../force-app/main/default/classes/QuoteProgressController.cls#L74)) y `SBQQ__R00N70000001lX7YEAU__r` ([:75](../../force-app/main/default/classes/QuoteProgressController.cls#L75)). |
| **Constantes `static final` UPPER_CASE** | [:25-36](../../force-app/main/default/classes/QuoteProgressController.cls#L25-L36); `APPROVED_STATUS_SET` con nombre de colección. Públicas para que los tests comparen contra la misma constante. |
| **Sin fallar en silencio** | `AuraHandledException` ([:81-87](../../force-app/main/default/classes/QuoteProgressController.cls#L81-L87)) + `.catch` que muestra el error ([quoteProgress.js:44-50](../../force-app/main/default/lwc/quoteProgress/quoteProgress.js#L44-L50)). |
| **Contexto correcto / `oldMap` / recursión / async** | No aplican: no hay guardado, ni comparación nuevo-vs-viejo, ni DML. |

---

## 6. Tests

Clase: [`QuoteProgressControllerTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls) · 12 métodos · **100%** de cobertura de `QuoteProgressController`. Setup ([:29-34](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L29-L34)): Account, Opportunity en Prospecting y Product2. Cada test llama al controller entre `Test.startTest()` / `Test.stopTest()`.

| Caso | Tipo | Test (archivo:método) | Qué verifica |
|---|---|---|---|
| Quote nueva, sin nada | Negativo | [`newQuoteAllStepsPendingTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L45) | 5 pasos, todos ❌ |
| Todo completo | Positivo | [`allStepsCompletedTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L63) | 5 ✅. CPQ apagado **solo** al tildar Ordered ([:72-75](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L72-L75)) |
| Orden y textos | Positivo | [`stepsOrderAndLabelsTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L90) | Los 5 labels del requirement, en orden |
| Solo líneas | Positivo (aislado) | [`quoteLinesAddedTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L112) | Solo el paso 1 ✅ |
| Solo documento | Positivo (aislado) | [`quoteDocumentCreatedTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L127) | Solo el paso 3 ✅ |
| Documento de **otra** Quote | Negativo | [`documentOfOtherQuoteNotCountedTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L144) | Paso 3 ❌ (filtra por Quote, no por Opportunity) |
| Solo Closed Won | Positivo (aislado) | [`opportunityClosedWonTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L163) | Solo el paso 4 ✅ |
| Sin Opportunity | Negativo / borde | [`quoteWithoutOpportunityTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L179) | Paso 4 ❌, sin NullPointerException |
| Approved / Presented / Accepted | Positivo | [`approvedStatusesTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L199) | Paso 2 ✅ en los 3 |
| Draft / In Review / Denied / Rejected | Negativo | [`notApprovedStatusesTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L216) | Paso 2 ❌ en los 4 |
| Eficiencia | Límites | [`singleQueryTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L238) | `Limits.getQueries() == 1` ([:243](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L243)) |
| Quote borrada | Negativo (error) | [`quoteNotFoundTest`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L254) | `AuraHandledException` con `QUOTE_NOT_FOUND_MESSAGE` ([:263-268](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L263-L268)) |

Los tests "aislados" usan el helper [`assertOnlyStepDone`](../../force-app/main/default/classes/QuoteProgressControllerTest.cls#L311): prueban que un paso se pone verde **sin arrastrar** a los demás (= pasos independientes).

**Lo que no tiene test y por qué:**
- **Bulk de 200:** no aplica, el método recibe una sola Quote.
- **El LWC (JS/HTML):** los tests de JavaScript (Jest) están fuera del training y no suman a la cobertura de Apex. Se probó en el org (5 Quotes en 5 estados, [DEV5.md §8](../code-review/DEV5.md#8-cómo-se-prueba-en-la-demo)).
- **"Solo Ordered":** exigiría repetir `TriggerControl`; lo cubre `allStepsCompletedTest` y en el org Q-00094.

Por qué `SBQQ.TriggerControl.disable()` y por qué solo ahí: [DEV5.md §2](../code-review/DEV5.md#sbqqtriggercontroldisable-en-allstepscompletedtest-y-por-qué-solo-ahí). Cobertura y Build Tracker: [DEV5.md §9](../code-review/DEV5.md#9-tests-cobertura-y-build-tracker).

---

## 7. Edge cases cubiertos y supuestos

### Edge cases

| Caso | Cómo se maneja | Dónde se prueba |
|---|---|---|
| Quote sin Opportunity | `if` antes de leer `IsWon` → paso 4 ❌ | `quoteWithoutOpportunityTest` |
| Documento de otra Quote de la misma Opportunity | Subquery por `SBQQ__Quote__c` → no cuenta | `documentOfOtherQuoteNotCountedTest` |
| Varios documentos (uno por versión) | `LIMIT 1`: alcanza con uno | Por diseño |
| Quote aprobada → Presented / Accepted | Sigue ✅ | `approvedStatusesTest` |
| Quote Denied / Rejected / In Review | ❌ | `notApprovedStatusesTest` |
| Quote borrada o sin acceso (`with sharing`) | `AuraHandledException` → texto rojo | `quoteNotFoundTest` |
| Amendment: Ordered sin aprobar ni Closed Won | Pasos independientes → 2/5 | Org: Q-00094 |
| Quote aprobada y **bloqueada** a la que se le genera documento | Funciona (el documento es un hijo) | Org: Q-00096 |
| Cambios en otra pantalla | ⟳ (sin caché, siempre fresco) | Demo |
| Usuario Direct Sales sin acceso a la clase | Permission set `Quote_Progress_Access` | QA-DEV5-01 |

Tabla completa: [DEV5.md §6](../code-review/DEV5.md#6-edge-cases).

### Supuestos (confirmados por Francisco, 05/10/2026)

- **"Approved" = Approved, Presented o Accepted** (los dos últimos son posteriores a la aprobación; hoy ninguna Quote del org los usa).
- **Los pasos son independientes**, no secuenciales.
- **Cualquier documento cuenta**, también uno generado con el template DRAFT ("Document Created", no "Final Document").
- **Solo escritorio:** en celular la Quote usa la página por defecto del sistema, sin el componente.
- Textos de la UI en inglés.

Lista completa: [DEV5.md §5](../code-review/DEV5.md#5-supuestos-y-decisiones). Limitaciones: [DEV5.md §10](../code-review/DEV5.md#10-limitaciones-conocidas-y-pendientes-de-qa).

---

## 8. Cinco preguntas probables del revisor

**1. "¿Por qué `@AuraEnabled` sin `cacheable=true`? ¿No es más rápido con caché?"**
Es más rápido, pero el caché puede devolver una respuesta vieja: aprobás la Quote, volvés, y sigue en ❌. Sin `cacheable`, cada apertura y cada ⟳ van al servidor. Además `cacheable` es obligatorio para `@wire`, y elegimos la llamada imperativa porque se lee como "llamar a una función" y refrescar es volver a llamarla.

**2. "¿Cómo sabe el componente qué Quote mostrar?"**
Por `@api recordId`. Cuando un LWC está en una record page, Salesforce completa solo la propiedad pública que se llama `recordId` con el Id del registro abierto. El JS se la pasa a Apex como `{ quoteId: this.recordId }`, con el mismo nombre que el parámetro del método.

**3. "¿Por qué no un trigger que guarde el progreso en un campo?"**
Porque el progreso depende de 4 objetos (Quote, Quote Line, Quote Document, Opportunity): harían falta triggers en todos para mantener un campo que nadie edita. Una query al abrir la página da el dato siempre fresco, con 0 DML y sin automatizaciones nuevas en la cadena del #31.

**4. "¿Para qué la clase interna `ProgressStep`? ¿No alcanzaba un Map?"**
Necesito mandar una lista **ordenada** con estructura, y Salesforce la convierte a JSON. Con un `Map<String, Boolean>` el orden quedaría a cargo del JS y los textos serían claves y datos a la vez. `@AuraEnabled` en cada campo es lo que hace que viajen en el JSON.

**5. "¿Qué pasa si un vendedor de Direct Sales abre la Quote y no tiene acceso?"**
Sin el permission set `Quote_Progress_Access`, la card mostraría *"You do not have access to the Apex class…"*: un LWC que llama a Apex necesita acceso a esa clase, y solo el admin lo tiene por defecto. Por eso creamos el permission set (aditivo, por usuario, sin tocar el perfil) y lo asignamos a sh.dsales y frandev.

Más preguntas (14 en total, incluidas el nombre raro de la relación, `IsWon` vs `StageName` y `TriggerControl`): [DEV5.md §7](../code-review/DEV5.md#7-preguntas-probables-del-code-review).
