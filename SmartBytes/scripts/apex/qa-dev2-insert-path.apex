// QA-DEV2-01 (ver docs/qa-pending.md)
// Crea una Order que nace con 'Not Needed' y le agrega un producto en la MISMA transacción,
// igual que CPQ. Esto dispara el camino del insert: afterInsert -> OrderActivationQueueable.
// Ejecutar con:
//   sf apex run --file scripts/apex/qa-dev2-insert-path.apex --target-org smartbytes

Account acc = [SELECT Id FROM Account WHERE Name = 'Burlington Textiles Corp of America' LIMIT 1];

PricebookEntry pricebookEntry = [
    SELECT Id, Pricebook2Id, UnitPrice
    FROM PricebookEntry
    WHERE Product2.Name = 'Monthly Named Users'
    AND Pricebook2.IsStandard = true
    AND IsActive = true
    LIMIT 1
];

Order ord = new Order();
ord.AccountId = acc.Id;
ord.EffectiveDate = Date.today();
ord.Status = 'Draft';
ord.Pricebook2Id = pricebookEntry.Pricebook2Id;
ord.SBQQ__PriceCalcStatus__c = 'Not Needed';
ord.Description = 'QA-DEV2-01: prueba del camino del insert (Queueable)';
insert ord;

OrderItem item = new OrderItem();
item.OrderId = ord.Id;
item.PricebookEntryId = pricebookEntry.Id;
item.Quantity = 1;
item.UnitPrice = pricebookEntry.UnitPrice;
insert item;

System.debug( 'QA-DEV2-01 Order creada: ' + ord.Id );
