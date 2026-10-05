# Build Tracker — SmartBytes CPQ (DEV #1 a #5)

**Última corrida:** 05/10/2026 20:02 UTC, Test Run `707fj000016kkZU`, después de la **revisión de calidad** (`ErrorLogUtil.saveLogsForFailedResults` unifica el registro de errores de 3 clases; ver DEV2.md). Deploy: dry-run `0Affj00000TafYdCAJ` (85/85) + quick deploy `0Affj00000TawCsCAJ`.

**Corrida anterior:** 05/10/2026 19:14 UTC, todos los tests locales (`sf apex run test --test-level RunLocalTests --code-coverage`), Test Run `707fj000016kYIt`. Corrida del **congelamiento del código** (constante `STATUS_ACTIVATED` unificada + comentarios traducidos al inglés). Deploy validado con dry-run (`0Affj00000TawcfCAB`, 83/83) y aplicado con quick deploy (`0Affj00000Tax45CAB`).

**Resultado:** 85 métodos de test, **85 pasan, 0 fallan** (Salesforce informa 94 porque cuenta los 9 `@testSetup`).
**Cobertura del org: 97%.** Mínimo por clase: 91%. Objetivo del Final Assignment: ≥ 85% ✅

## Código Apex (listo para copiar)

| DEV | Componente | Tipo | Test Class | Tests | Última corrida | Cobertura |
|---|---|---|---|---|---|---|
| #2 | OrderTrigger | Trigger | OrderTriggerHandlerTest | 11 | 05/10/2026 | 100% |
| #2 | OrderTriggerHandler | Class | OrderTriggerHandlerTest | (los mismos 11) | 05/10/2026 | 100% |
| #2 | OrderActivationQueueable | Class (Queueable) | OrderTriggerHandlerTest | (los mismos 11) | 05/10/2026 | 100% |
| #2 | ErrorLogUtil | Class | ErrorLogUtilTest | 4 | 05/10/2026 | 100% |
| #1 | QuoteTrigger | Trigger | QuoteTriggerHandlerTest | 12 (8 del DEV #1 + 4 del DEV #3) | 05/10/2026 | 100% |
| #1 / #3 | QuoteTriggerHandler | Class | QuoteTriggerHandlerTest | (los mismos 12) | 05/10/2026 | 91% |
| #1 | QuoteExpirationBatch | Class (Batch) | QuoteExpirationBatchTest | 8 | 05/10/2026 | 93% |
| #1 | QuoteExpirationScheduler | Class (Schedulable) | QuoteExpirationSchedulerTest | 1 | 05/10/2026 | 100% |
| #4 | SubscriptionTrigger | Trigger | SubscriptionTriggerHandlerTest | 9 | 05/10/2026 | 100% |
| #4 | SubscriptionTriggerHandler | Class | SubscriptionTriggerHandlerTest | (los mismos 9) | 05/10/2026 | 100% |
| #4 | ActiveSubscriptionCounter | Class | ActiveSubscriptionCounterTest (+ SubscriptionTriggerHandlerTest, ActiveSubscriptionRecountBatchTest) | 10 | 05/10/2026 | 100% |
| #4 | ActiveSubscriptionRecountBatch | Class (Batch) | ActiveSubscriptionRecountBatchTest | 3 | 05/10/2026 | 100% |
| #4 | ActiveSubscriptionRecountScheduler | Class (Schedulable) | ActiveSubscriptionRecountSchedulerTest | 1 | 05/10/2026 | 100% |
| #3 | ContractTrigger | Trigger | ContractTriggerHandlerTest | 5 | 05/10/2026 | 100% |
| #3 | ContractTriggerHandler | Class | ContractTriggerHandlerTest (+ RenewalQuoteBatchTest) | (los mismos 5) | 05/10/2026 | 100% |
| #3 | RenewalQuoteBatch | Class (Batch) | RenewalQuoteBatchTest | 8 | 05/10/2026 | 95% |
| #3 | RenewalQuoteScheduler | Class (Schedulable) | RenewalQuoteSchedulerTest | 1 | 05/10/2026 | 100% |
| #5 | QuoteProgressController | Class (`@AuraEnabled`) | QuoteProgressControllerTest | 12 | 05/10/2026 | 100% |
| — | TestDataFactory | Test utility (`@IsTest`) | Usada por todas | — | 05/10/2026 | No cuenta (clase de test) |

**Total de métodos de test:** 11 + 4 + 12 + 8 + 1 + 9 + 10 + 3 + 1 + 5 + 8 + 1 + 12 = **85**.

## Líneas sin cubrir (todas son ramas de error)

| Clase | Líneas | Por qué no se cubren |
|---|---|---|
| QuoteTriggerHandler | 205-206, 209, 211-213 | Falla de un email y el `catch` del envío: en un test no se puede hacer fallar `Messaging.sendEmail` |
| QuoteExpirationBatch | 112-113 | Error Log cuando un recall falla: no se puede forzar con datos de test |
| RenewalQuoteBatch | 123, 139 | `return` de seguridad: todos los updates fallan, o no hay Opportunity en Prospecting |

## Componentes sin cobertura de Apex (probados en el org)

| DEV | Componente | Tipo | Cómo se probó |
|---|---|---|---|
| #5 | quoteProgress | Lightning Web Component | En el org, con Q-00079, Q-00108, Q-00074, Q-00094 y Q-00096 (05/10/2026). Jest está fuera del training |
| #5 | Training_Quote_Page | FlexiPage (IC) | Deploy validado con dry-run; es el org default de la Quote |
| #5 | Quote_Progress_Access | Permission Set | Asignado a sh.dsales y frandev |
| #4 | Contract.Active_Subscriptions__c + Active_Subscriptions_Access | Campo + Permission Set | En el org (DEV4.md) |
| #2 | Error_Log__c + Error_Log_Access | Objeto + Permission Set | En el org (DEV2.md) |

## Jobs programados

| Job | Clase | Cron | Hora | DEV |
|---|---|---|---|---|
| Quote Expiration Recall - Nightly | QuoteExpirationScheduler | `0 0 1 * * ?` | 1:00 | #1 |
| Active Subscriptions Recount - Nightly | ActiveSubscriptionRecountScheduler | `0 0 2 * * ?` | 2:00 | #4 |
| Renewal Quote Generation - Nightly | RenewalQuoteScheduler | `0 0 3 * * ?` | 3:00 | #3 |
