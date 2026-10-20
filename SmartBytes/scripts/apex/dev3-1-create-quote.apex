// DEV #3 - Preparación de datos, paso 1 de 3 (ver docs/code-review/DEV3.md, sección 8)
// Crea una Opportunity + Quote Primary con Monthly Named Users x 125, con inicio en el PASADO
// para que el Contract venza dentro de los próximos 30 días (ventana del RenewalQuoteBatch).
// Después hay que esperar ~20 s a que CPQ calcule los precios y correr el paso 2.
// Antes de ejecutar: completar OPPORTUNITY_NAME y START_DATE.
// Ejecutar con:
//   sf apex run --file scripts/apex/dev3-1-create-quote.apex --target-org smartbytes

String OPPORTUNITY_NAME = 'DEV3 E2E Test - Renewal';
Date START_DATE = Date.newInstance( 2025, 11, 1 ); // 12 meses -> vence el 2026-10-31

Account acc = [SELECT Id FROM Account WHERE Name = 'Burlington Textiles Corp of America' LIMIT 1];
Pricebook2 standardPricebook = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
PricebookEntry entry = [
    SELECT Id, Product2Id
    FROM PricebookEntry
    WHERE Pricebook2Id = :standardPricebook.Id
    AND Product2.Name = 'Monthly Named Users'
    AND IsActive = true
    LIMIT 1
];

Opportunity opp = new Opportunity();
opp.Name = OPPORTUNITY_NAME;
opp.AccountId = acc.Id;
opp.StageName = 'Prospecting';
opp.CloseDate = Date.today();
opp.Pricebook2Id = standardPricebook.Id;
insert opp;

SBQQ__Quote__c quote = new SBQQ__Quote__c();
quote.SBQQ__Opportunity2__c = opp.Id;
quote.SBQQ__Account__c = acc.Id;
quote.SBQQ__Primary__c = true;
quote.SBQQ__StartDate__c = START_DATE;
quote.SBQQ__SubscriptionTerm__c = 12;
quote.SBQQ__PaymentTerms__c = 'Net 30'; // sin descuento + Net 30 -> Auto_Approval
quote.SBQQ__PricebookId__c = standardPricebook.Id;
insert quote;

SBQQ__QuoteLine__c line = new SBQQ__QuoteLine__c();
line.SBQQ__Quote__c = quote.Id;
line.SBQQ__Product__c = entry.Product2Id;
line.SBQQ__PricebookEntryId__c = entry.Id;
line.SBQQ__Quantity__c = 125;
insert line;

System.debug( 'DEV3 Opportunity: ' + opp.Id + ' | Quote: ' + quote.Id );
