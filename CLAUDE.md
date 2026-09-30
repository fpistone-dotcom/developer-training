# CLAUDE.md — SmartBytes CPQ (FirstChair New Hire Training · Final Assignment)

Este archivo le da a Claude Code todo el contexto del proyecto. Leelo completo antes de hacer cualquier cosa.

---

## 1. Cómo trabajar conmigo (LO MÁS IMPORTANTE)

Soy Francisco. Estoy en el Salesforce Developer New Hire Training de FirstChair y este es mi proyecto final. **Mi objetivo principal es aprender**, no terminar rápido. Al final tengo que presentar este código en un **Code Review** frente al equipo del cliente, explicar cada decisión de diseño y responder preguntas, así que tengo que entender todo como si lo hubiera escrito de cero.

Reglas:

- **Respondé siempre en español (rioplatense está bien).** El código, los nombres de clases/métodos y los comentarios del código van en inglés, como es estándar.
- **Modo aprendizaje:** antes de escribir código, explicame el diseño en palabras simples: qué vamos a construir, por qué así y qué alternativas había. Después construilo en pasos chicos, explicando cada bloque.
- **El código lo escribís vos, yo lo tengo que entender.** No me pidas que escriba partes. Escribí todo, pero explicame cada bloque para que pueda defenderlo en el Code Review.
- **Explicá el "por qué" de Salesforce:** contexto de trigger (before/after), bulkificación, governor limits, por qué una query va afuera del loop, etc. Asumí que sé lo básico de Apex pero que nunca armé un proyecto real completo.
- **No avances de un requirement al siguiente sin mi confirmación.**
- **No toques configuración declarativa (IC) sin preguntarme.** Ya está terminada y probada (ver sección 4).
- Al terminar cada requirement, dame un **resumen para el Code Review**: decisiones de diseño, supuestos, edge cases cubiertos y cómo se prueba en la UI.
- Soy nuevo en Claude Code: si un comando de terminal o de `sf` es nuevo, explicame qué hace antes de correrlo.

---

## 2. Contexto del proyecto

- **Cliente ficticio:** SmartBytes. Vende servicios profesionales y productos de suscripción con **Salesforce CPQ** (paquete gestionado, namespace `SBQQ`, versión 240.5, CPQ clásico).
- **Org:** Developer Edition de training — `firstchair-dev-ed.develop.my.salesforce.com`
- **Mi rol:** hago tanto la parte IC (admin/config, ya terminada) como la DEV (código, lo que falta).
- **Documento de requirements:** "SmartBytes Use Case Overview V2" (los requirements DEV están copiados abajo, textuales).
- **Mentor:** Facu.

### Entregables finales
- Cobertura de código ≥ **85%** (Test Classes que pasan).
- Demo en el **org deployado** (graded por leaders y peers, > 65%).
- End of Week Run Summary (Test Rail) y Build Tracker.
- **Code Review**: explicar decisiones de diseño y supuestos, cubrir requirements y edge cases, código limpio y legible con comentarios, DRY, **bulkificación**, eficiencia con los límites y **ejecución en el contexto de trigger correcto**.

---

## 3. Estándares de código (FirstChair / Salesforce best practices)

- **Un solo trigger por objeto** y sin lógica adentro: el trigger delega en una clase **handler** (`OrderTriggerHandler`, etc.).
- **Bulkificado siempre:** nada de SOQL ni DML dentro de loops. Trabajar con `Set<Id>`, `Map<Id, SObject>` y listas.
- Usar el **contexto de trigger correcto:** before para modificar campos del mismo registro (sin DML), after para registros relacionados o cuando se necesita el Id.
- Detectar **cambios reales de campos** comparando `Trigger.new` con `Trigger.oldMap` para no reprocesar.
- Evitar recursión cuando corresponda.
- **Tests:** una `TestDataFactory` reutilizable, `@TestSetup`, `Test.startTest()/stopTest()`, **asserts con mensaje**, casos positivos, negativos y bulk (200 registros).
- Comentarios claros (ApexDoc en clases y métodos públicos). Nombres descriptivos.

### 3.1 Nivel del training — usá SOLO lo que vi en el curso

El código tiene que parecer escrito por alguien que acaba de terminar este training, no por un senior. Esta sección resume el "Salesforce Developer Training Recap" de FirstChair, módulo por módulo.

**Módulo 1 — Apex Basics**
- Tipado fuerte: toda variable con tipo. Primitivos más usados: String, Integer, Decimal, Boolean, Date, Datetime, Id. Tener en cuenta el Field Type del campo al leer/escribir.
- Colecciones: List (ordenada, por índice), Set (sin orden ni duplicados), Map (clave-valor, clave única). Nombres en plural o con el tipo: `orderList`, `orderIdSet`, `orderByIdMap` (patrón `valorPorClaveMap`, como `monthNameByNumberMap`).
- Condicionales: if / else if / else, switch, ternario. Espacio antes y después de los paréntesis. Nada de condicionales de una sola línea (siempre con llaves).
- Loops: for tradicional, for mejorado (el más usado), for con SOQL, while, do-while.
- Clases: la mayoría de los métodos `static`. Clases en UpperCamelCase; variables y métodos en camelCase; constantes `static final` en UPPER_CASE.
- sObjects: instancia nueva para crear registros, campos con notación de punto y API Name.
- DML: insert, update, upsert, delete, undelete, siempre sobre listas. El Id es el único campo del sistema que se completa solo después de un insert.
- SOQL: WHERE para traer solo lo necesario; si la query pasa ~100 caracteres, cada cláusula en su propia línea; relaciones lookup para datos del padre y subqueries para hijos.

**Módulo 2 — Triggers**
- Un solo trigger por objeto, llamado `ObjetoTrigger` (ej. `OrderTrigger`).
- Sin lógica de negocio: usa las variables de contexto (`Trigger.isBefore`, `Trigger.isUpdate`, etc.) y llama a métodos `public static` del handler, pasando `Trigger.new` y `Trigger.oldMap`. Ej.: `OrderTriggerHandler.beforeUpdate(Trigger.new, Trigger.oldMap)`.
- Handler: `public with sharing class ObjetoTriggerHandler`, con métodos de entrada por contexto (`beforeInsert`, `afterUpdate`, etc.) que llaman a métodos `private static` con la lógica.
- **Before** = cambios en los MISMOS registros, sin DML (el Id no existe todavía en before insert). **After** = cambios en registros RELACIONADOS, con DML explícito.

**Governor Limits (multitenant)**
- Nunca SOQL ni DML dentro de un for loop.
- Usar `Trigger.oldMap` para comparar nuevo vs viejo y correr la lógica solo si el campo cambió.
- Poner un condicional antes de la SOQL para que corra solo cuando hace falta (salvo en insert).
- WHERE para reducir el volumen de datos.
- No hacer DML sobre el mismo objeto más de una vez en el mismo contexto de trigger.
- Una excepción no atrapada hace rollback de toda la transacción.

**Módulo 3 — Test Classes**
- Nombre: `ClaseTest` (ej. `OrderTriggerHandlerTest`), anotada `@IsTest`, con métodos `@isTest` nombrados `metodoTest`.
- `@testSetup` para los datos comunes de la clase.
- Cada método de test corre con su propia base de datos (se hace rollback al terminar) y sus propios Governor Limits.
- Cobertura mínima para deployar: 75%. **Para el Final Assignment: 85%.**
- Manejo de excepciones con try / catch / finally, sin fallar en silencio. Las Limit Exceptions no se pueden atrapar.

**Módulo 4 — Asynchronous Apex**
- **Future:** lógica async simple (callouts, límites extra, Mixed DML). Solo recibe primitivos o colecciones de primitivos; no devuelve Id de AsyncApexJob.
- **Queueable:** cuando hay que encadenar jobs o pasar sObjects. `execute()` obligatorio. Bloquear el chaining en tests con `!Test.isRunningTest()`.
- **Batch:** gran volumen de registros. En tests, `execute()` corre una sola vez.
- **Scheduled:** implementa `Schedulable`; delegar la lógica en otra clase, no ponerla en `execute()`.

**Final Assignment (Módulo 5)**
- Mantener actualizado el **Build Tracker**: qué Test Class cubre qué clase/trigger, fecha de la última corrida y % de cobertura. Al terminar cada requirement, dame esos datos listos para cargar.

**Extras que NO están en el curso pero usamos igual (explicámelos cuando aparezcan):**
- `Test.startTest()` / `Test.stopTest()`: necesarios para que los Queueable/Batch se ejecuten dentro del test y para medir límites por separado.
- `System.assertEquals` con mensaje, y casos bulk de 200 registros.
- Una `TestDataFactory` compartida, para no repetir la creación de datos (DRY).
- `Error_Log__c` + clase utilitaria de logging (decisión de diseño del DEV #2).
- Comentarios ApexDoc en clases y métodos públicos.

**Qué evitar (fuera del nivel del curso):** frameworks de trigger con interfaces o clases abstractas, fflib, inyección de dependencias, genéricos, Dynamic Apex / Schema describe, Custom Metadata para configuración, `Database.Stateful`, clases wrapper complejas y atajos "ingeniosos" en una sola línea (por ejemplo `new Map<Id, Order>(list).keySet()`: preferí un for simple). Si algo fuera del curso es realmente necesario, **primero explicame por qué y ofreceme la alternativa más simple**; decido yo.

---

## 4. Estado actual del IC (todo terminado — NO modificar sin preguntar)

Automatizaciones y reglas relevantes para los DEV:

| Componente | Tipo | Qué hace |
|---|---|---|
| `Block_ClosedWon_Without_Approved_Quote` | Validation Rule (Opportunity) | Req #30: no deja pasar a Closed Won si la Primary Quote no está Approved. Aplica solo al perfil Direct Sales. |
| `Auto_Create_Order_On_Closed_Won` | Record-Triggered Flow (Opportunity, after save) | Req #31: al pasar a Closed Won, marca la Primary Quote aprobada como `SBQQ__Ordered__c = true`. CPQ crea la **Order + Order Products** en estado Draft. |
| `Auto_Contract_Order_On_Activation` | Record-Triggered Flow (Order, after save) | Req #31: cuando una Order **pasa** a `Status = Activated`, la marca `SBQQ__Contracted__c = true`. CPQ crea **Contract + Subscriptions + Assets** (proceso asíncrono, tarda unos segundos). |
| Approval Process de Quote | Approval Process | Req #24–26: aprobaciones según la tabla Quote Approval. La Quote queda bloqueada tras el submit. **Hay 2 procesos activos, con criterios de entrada opuestos (cada Quote entra en exactamente uno):** **`Auto_Approval`**: `AND( ISPICKVAL(SBQQ__PaymentTerms__c, "Net 30"), OR( ISBLANK(SBQQ__CustomerDiscount__c), SBQQ__CustomerDiscount__c < 0.15 ) )`; se aprueba sola al hacer Submit. **`Quote_Approval_V2`**: `NOT( <la misma fórmula> )`; 3 pasos en fila: **Finance** (`PaymentTerms != Net 30`, usuario frandev; si no → siguiente paso), **Manager** (`CustomerDiscount >= 15`, `Approving_Manager__c`; si no → aprobar) y **Director** (`>= 25`, `Approving_Director__c`). Inactivos (Obsolete, no borrados, sirven para rollback): `Discount_Approval`, `Billing_Approval` y `Quote_Approval` (V1). |
| `OrderTrigger` + `OrderTriggerHandler` + `OrderActivationQueueable` | Apex (DEV #2, **hecho**) | Activa la Order cuando su `SBQQ__PriceCalcStatus__c` es o pasa a `Completed`/`Not Needed`. Update: en before update, sin DML. Insert: con un Queueable. Errores en `Error_Log__c` (vía `ErrorLogUtil`). Tests: 14/14, cobertura 100%. |
| `QuoteTrigger` + `QuoteTriggerHandler` | Apex (DEV #1 Parte A, **hecho**) | En before insert/update, cuando `SBQQ__Status__c` pasa a (o nace) `Approved`, pone `SBQQ__ExpirationDate__c = hoy + 30`. Sin SOQL ni DML. Tests: 8/8, cobertura 100%. Parte B (Batch + Scheduler del recall) pendiente: ver `docs/code-review/DEV1.md`. |

**Cadena completa del #31 (100% automática desde el DEV #2):**
`Opportunity → Closed Won` → (Flow 1) Quote Ordered → CPQ crea Order Draft (`Not Started` → `Queued`) → calculador de CPQ (`OrderPriceCalculatorService`) pasa la Order a `Not Needed` → **(DEV #2, before update) Order Activated** → (Flow 2) Order Contracted → CPQ crea Contract + Subscription + Asset.

Verificado end-to-end el 29/09/2026: Opportunity "DEV2 E2E Test - Order Activation", Q-00057 → Order 00000120 activada ~3 s después de crearse → Contract 00000108 + SUB-0000011, sin errores.

---

## 5. Cosas que aprendimos del org (importante para testear)

- **Subscription vs Asset:** CPQ genera **Subscription** solo para productos con `SBQQ__SubscriptionPricing__c` completo (Fixed Price / Percent Of Total). Los productos sin ese campo generan **Asset**. **Si no hay ninguna Subscription, CPQ no crea Contract.** Para probar Contracts usar un producto de suscripción (por ejemplo "Monthly Named Users", Fixed Price) y no "RFID Key Card" (que no es de suscripción).
- **Calculador asíncrono de CPQ:** después de crear o editar Quote Lines, CPQ recalcula precios en un Queueable. Si se marca la Quote como Ordered antes de que termine, falla con "Order Products must have a Unit Price". Hay que esperar unos segundos.
- **Contracting es asíncrono:** al marcar la Order como Contracted corre `QueueableContractOrdersClient`. El Contract aparece unos segundos después. Tenerlo en cuenta en tests y demos.
- El **Contract nace en `Status = Draft`**. Nadie lo activa automáticamente todavía (relevante para el DEV #3).
- **Corregido con debug log (29/09/2026):** la Order generada por CPQ **no** nace con `Not Needed`. Nace con `SBQQ__PriceCalcStatus__c = 'Not Started'` (default del campo), CPQ la pasa a `Queued` en la misma transacción, y su Queueable `OrderPriceCalculatorService` la pasa a `Not Needed` unos segundos después. `Not Needed` era el estado final, no el inicial.
- Los productos (OrderItems) se insertan en la misma transacción que la Order, inmediatamente después de ella.
- Validation rule nativa de CPQ `Cannot_Contract_New_Order`: no se puede contratar una Order que no esté activada.
- Los logs de Apex del paquete CPQ están ocultos (paquete protegido): se ven SOQL/DML, no su lógica interna.
- El registro de Quote aprobado queda bloqueado por el Approval Process. La API permite editar, pero el Quote Line Editor no.
- **Acciones de los Approval Processes de Quote (idénticas en todos, field updates en `Workflow:SBQQ__Quote__c`):** Submit → `Set_Quote_Status_In_Review`; aprobación final → `Set_Quote_Status_Approved` + `Set_Quote_Template_Final` y **bloquea**; rechazo → `Set_Quote_Status_Denied` (desbloquea); recall → `Set_Quote_Status_Draft`. O sea: `SBQQ__Status__c = Approved` lo pone un **field update**, que vuelve a disparar los triggers de update.
- **Gap de IC cerrado (30/09/2026):** las Quotes con descuento < 15% (o vacío) y Net 30 no entraban en ningún proceso ("No applicable approval process"), así que nunca llegaban a Approved y el Req #30 bloqueaba el Closed Won. Se creó `Auto_Approval` (metadata en `force-app/main/default/approvalProcesses/`): criterio de entrada por fórmula (en fórmula un percent vale 0.15, no 15), `processOrder = 3` y un único step con criterio `FALSE` + `ifCriteriaNotMet = ApproveRecord`, que aprueba al hacer Submit. Probado con la Opportunity "IC Test - Auto Approval": **Q-00058** (sin descuento) y **Q-00059** (10%) → Submit → Approved por `Auto_Approval`, con template Final.
- **Rediseño de aprobaciones (30/09/2026):** con 3 procesos separados, Salesforce corre **un solo proceso por Submit**, así que una Quote con descuento ≥ 15% **y** Payment Terms ≠ Net 30 solo pasaba por el Manager y Finance nunca la veía. **Supuesto:** el Worksheet no define el caso combinado; se interpretó que cada motivo requiere su aprobador, en secuencia Finance → Manager → Director.
- **Aprendizaje: Salesforce solo auto-aprueba desde el primer paso; por eso son dos procesos con criterios opuestos.** Un proceso único con los 3 pasos (V1, `Quote_Approval`) **rechazaba** las Quotes sin motivos de aprobación: si se saltea el paso 1 y se "aprueba" en un paso posterior sin que nadie haya aprobado, termina en Rejected, tanto con `GotoNextStep` como con `ApproveRecord`. Después de una aprobación real, en cambio, saltear los pasos restantes sí aprueba.
- **Reglas de metadata de Approval Process:** (1) el último paso de un proceso de varios pasos no acepta `ifCriteriaNotMet`; (2) una vez activado, no se pueden agregar ni quitar pasos, ni cambiar un `ifCriteriaNotMet` desde o hacia `GotoNextStep`, ni siquiera desactivándolo: hay que crear un proceso nuevo (por eso existe V2); (3) el criterio de entrada **sí** se puede editar con el proceso activo; (4) un proceso con aprobaciones asociadas no se puede borrar, solo desactivar (en `ProcessDefinition` queda como `Obsolete`).
- **Prueba end-to-end de las aprobaciones (30/09/2026, Opportunity "IC Test - Auto Approval", aprobando con frandev):** Q-00072 (sin desc., Net 30) y Q-00073 (10%, Net 30) → `Auto_Approval` → Approved. Q-00074 (20%, Net 30) → Manager → Approved. Q-00075 (0%, Net 60) → Finance → Approved. Q-00076 (20%, Net 60) → Finance → Manager → Approved. Q-00077 (30%, Net 30) → Manager → Director → Approved. Q-00078 (0%, Payment Terms vacío) → Finance → Approved. Todas quedaron con vencimiento hoy + 30 (DEV #1). Quedan Quotes de prueba viejas (Q-00062 a Q-00071) en estados Denied / In Review de las pruebas de V1 y V2.
- **"Enable record locking and unlocking in Apex" está DESACTIVADO** en Process Automation Settings: `Approval.isLocked` / `Approval.lock` / `Approval.unlock` tiran `NoAccessException`. Relevante para el recall del DEV #1.

**Datos de prueba existentes:** Opportunity "Test Opportunity" (Account: Burlington Textiles Corp of America), Quote Q-00056 (Primary). Las últimas pruebas generaron Order 00000119, Contract 00000107 y SUB-0000010. Prueba end-to-end del DEV #2: Opportunity "DEV2 E2E Test - Order Activation" (006fj00000N7Le6AAF), Q-00057 → Order 00000120, Contract 00000108, SUB-0000011.

---

## 6. Requirements DEV (textuales + desglose)

Orden propuesto: **#2 → #1 → #4 → #3 → #5**.

### DEV #2 — Activación automática de la Order  ← EMPEZAR ACÁ
> "As part of the Provisioning Team, I want the ability to automatically activate an Order record whenever it is created and the Price Calculation Status on the Order is updated to either 'Completed' or 'Not Needed'."

- **Qué pide:** cuando se crea una Order y su `SBQQ__PriceCalcStatus__c` es o pasa a ser "Completed" o "Not Needed", poner `Status = 'Activated'`.
- **Piezas:** `OrderTrigger` + `OrderTriggerHandler` + test class.
- **A investigar antes de diseñar (explicámelo):**
  - En qué orden CPQ inserta la Order y los Order Products. Salesforce no deja activar una Order sin productos. Si la Order ya nace con "Not Needed", activarla en el insert puede fallar porque todavía no tiene items. Hay que ver el orden de eventos y decidir el contexto correcto (after update, Queueable, etc.).
  - Cubrir insert y update. Solo reaccionar cuando el valor **cambia** a Completed/Not Needed.
- **Encaja con:** Flow 2 del IC. Una vez activada, el Flow la marca Contracted.

### DEV #1 — Vencimiento automático de la Quote
> "Whenever a Quote record is approved, the Quote Expiration Date should be set to 30 days from the date in which it was approved. If a Quote reaches the Quote Expiration Date and the related Opportunity is still not 'Closed Won,' then the Quote approvals should be recalled."

- **Piezas:** trigger en `SBQQ__Quote__c` (al pasar `SBQQ__Status__c` a Approved → `SBQQ__ExpirationDate__c = hoy + 30`) + **Scheduled Apex / Batch** diario (Quotes vencidas cuya Opportunity no esté Closed Won → "recall") + tests.
- **Ojo:** CPQ ya setea una fecha de vencimiento por defecto (Default Quote Validity = 30 días desde la creación). Esto la tiene que pisar al aprobar.
- **Decisión de diseño a charlar:** una aprobación ya terminada no se puede "recallear" con la API estándar (el recall aplica a aprobaciones pendientes). Hay que definir qué significa "recall" acá: por ejemplo, desbloquear el registro (`Approval.unlock`) y volver el status a Draft/Recalled. Consultarlo con el mentor si hace falta.

### DEV #4 — Contador de Subscriptions activas en el Contract
> "As a Sales User, I need a field on the Contract that quickly identifies how many active Subscriptions are currently related to the Contract."

- **Piezas:** campo número nuevo en Contract + trigger en `SBQQ__Subscription__c` (insert, update, delete, undelete) + tests.
- `SBQQ__Subscription__c.SBQQ__Contract__c` es **lookup**, no master-detail, así que no se puede usar un roll-up summary nativo (explicámelo).
- **Definir "activa":** por ejemplo, fechas vigentes (start ≤ hoy ≤ end) y sin `SBQQ__TerminatedDate__c`. Documentar el supuesto.

### DEV #3 — Renewal Opportunity automática
> "As a Sales User, I would like a Renewal Opportunity to automatically be generated when a Contract is activated so that I can accurately forecast future sales. In addition, 30 days before the end of a Contract, I would like the Renewal Opportunity to be updated and a Renewal Quote generated so that my team can start preparing for the renewal sale. When this happens, the Owner of the Quote should have an email notification sent to them indicating that a Renewal Quote has been created, and the email should include a link to the Quote."

- **Piezas:** trigger en Contract (al pasar a Activated) + **Scheduled Apex** (contratos que vencen en 30 días) + envío de email con link a la Quote + tests.
- **A investigar:** CPQ tiene campos nativos en Contract, `SBQQ__RenewalForecast__c` (genera la Renewal Opportunity) y `SBQQ__RenewalQuoted__c` (genera la Renewal Quote). Probablemente la solución correcta sea **activar esos flags** en lugar de crear los registros a mano. Verificarlo en el org.
- **Pendiente:** el Contract nace en Draft. Definir cómo se activa en la demo (manual u otra automatización).
- Relacionado con la demo: los Contract Change Use Cases (Amend a los 6 y 9 meses) tienen que verse reflejados en la Renewal Opportunity.

### DEV #5 — Barra de progreso en la Quote
> "As a Sales User, I would like to be able to see a User-friendly UI on the Quote record that shows my current progress in the Quoting process. Specifically, I would like the following tasks to either have a green checkmark or red 'X': Quote Lines Added, Quote Approved, Quote Document Created, Opportunity Closed Won, Quote Ordered."

- **Piezas:** Apex controller (`@AuraEnabled`) + **Lightning Web Component** en la record page de la Quote + tests del controller.
- **Posibles fuentes de cada paso** (a validar): Quote Lines → `SBQQ__LineItemCount__c > 0`; Approved → `SBQQ__Status__c = 'Approved'`; Document → existen registros `SBQQ__QuoteDocument__c`; Closed Won → Opportunity `IsWon`; Ordered → `SBQQ__Ordered__c`.

---

## 7. Flujo de trabajo con Salesforce CLI

```bash
sf org login web --alias smartbytes          # conectar el org (una vez)
sf config set target-org smartbytes           # dejarlo como org por defecto
sf project retrieve start --metadata ApexClass ApexTrigger   # traer código existente
sf project deploy start --source-dir force-app               # subir cambios
sf apex run test --code-coverage --result-format human --wait 10   # correr tests + cobertura
sf data query --query "SELECT Id, Status FROM Order LIMIT 5"       # consultar datos
```

Usar **git** desde el inicio, con un commit por avance significativo, para tener historial para el Code Review.
