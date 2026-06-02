/*
Requirement #1.10: Using sObjects
Note: For the following exercises, we will be creating new instance of records in memory - we will not be interacting with the Salesforce Database. 
We will talk about interacting with the Salesforce database in the next lesson on DML.

Create a new instance of the following sObjects and populate at least 5 fields on each new instance. You choose the fields! Print out each instance to view it in 
the Developer Console. 
Hint - Use JetStream to easily find the API Field Names of the different sObjects.

Account
Opportunity
Opportunity Product
CPQ Quote (SBQQ__Quote__c)
CPQ Quote Line (SBQQ__QuoteLine__c)
Contact
Order
Order Item
Product
Task

Using a traditional for loop, create 10 SBQQ__Quote__c records and add then to a List. Print out this List.

Using the same instances of records you created in the first exercise, print out at least one field you populated on each of the 10 sObjects. 
For example, if you created a new instance of a Product record and populated the Description field, print out that field to the Developer Console.

*/

// Create a new instance of each sObject and populate at least 5 fields

// 1. Account
Account acc = new Account();
acc.Name = 'Acme Technology Solutions';
acc.Industry = 'Technology';
acc.BillingCity = 'San Francisco';
acc.BillingState = 'CA';
acc.NumberOfEmployees = 500;
System.debug('Account Created: ' + acc);

// 2. Opportunity
Opportunity opp = new Opportunity();
opp.Name = 'New Business Deal';
opp.StageName = 'Prospecting';
opp.CloseDate = Date.today().addDays(60);
opp.Amount = 100000;            
opp.LeadSource = 'Web';
System.debug('Opportunity Created: ' + opp);


// 3. Opportunity Product (OpportunityLineItem)
OpportunityLineItem oppLineItem = new OpportunityLineItem();
oppLineItem.Quantity = 10;
oppLineItem.UnitPrice = 5000;
oppLineItem.ServiceDate = Date.today();
oppLineItem.Description = 'Enterprise Software License';
oppLineItem.SortOrder = 1; // <-- 5to campo agregado
System.debug('Opportunity Product Created: ' + oppLineItem);

// 4. CPQ Quote (SBQQ__Quote__c)
SBQQ__Quote__c cpqQuote = new SBQQ__Quote__c();
cpqQuote.Name = 'Quote for Acme Technology Solutions';
cpqQuote.SBQQ__PaymentTerms__c = 'Net 30';
cpqQuote.SBQQ__TotalPrice__c = 45000;
cpqQuote.SBQQ__Status__c = 'Draft';
cpqQuote.SBQQ__ExpirationDate__c = Date.today().addDays(30);
System.debug('CPQ Quote Created: ' + cpqQuote);

// 5. CPQ Quote Line (SBQQ__QuoteLine__c)
SBQQ__QuoteLine__c quoteLine = new SBQQ__QuoteLine__c();
quoteLine.SBQQ__Quantity__c = 10;
quoteLine.SBQQ__Discount__c = 10;
quoteLine.SBQQ__ListPrice__c = 5000;
quoteLine.SBQQ__UnitPrice__c = 5000;
quoteLine.SBQQ__TotalPrice__c = quoteLine.SBQQ__Quantity__c * quoteLine.SBQQ__UnitPrice__c;
System.debug('CPQ Quote Line Created: ' + quoteLine);   

// 6. Contact
Contact con = new Contact();
con.FirstName = 'John';
con.LastName = 'Doe';
con.Email = 'JohnDoe@firstchair.com';
con.Phone = '555-123-4567';
con.MailingCity = 'San Francisco';
System.debug('Contact Created: ' + con);

// 7. Order
Order ord = new Order();
ord.BillingCity = 'San Francisco';
ord.ShippingCity = 'San Francisco';
ord.EffectiveDate = Date.today();
ord.Status = 'Draft';
ord.Description = 'Order for Acme Technology Solutions';
System.debug('Order Created: ' + ord); 

// 8. Order Item (OrderItem)
OrderItem ordItem = new OrderItem();
ordItem.Description = 'Enterprise Software License';
ordItem.ServiceDate = Date.today();
ordItem.Quantity = 10;  
ordItem.UnitPrice = 5000;
ordItem.EndDate = Date.today().addDays(30); // <-- 5to campo agregado
System.debug('Order Item Created: ' + ordItem);

// 9. Product
Product2 prod = new Product2();
prod.Name = 'Enterprise Software License';
prod.Description = 'License for enterprise software solution';
prod.Family = 'Software';
prod.ProductCode = 'ENT-001';
prod.IsActive = true;
System.debug('Product Created: ' + prod);

// 10. Task
Task tsk = new Task();
tsk.Subject = 'Follow up with Acme Technology Solutions';
tsk.Status = 'Not Started';
tsk.Priority = 'High';
tsk.ActivityDate = Date.today().addDays(7);
tsk.Description = 'Follow up on the new business deal opportunity';
System.debug('Task Created: ' + tsk);

System.debug('===== EXERCISE 1 COMPLETE: All 10 sObject instances created =====');


// Using a traditional for loop, create 10 SBQQ__Quote__c records and add them to a List

List<SBQQ__Quote__c> quoteList = new List<SBQQ__Quote__c>();

for (Integer i = 1; i <= 10; i++) {
    SBQQ__Quote__c newQuote = new SBQQ__Quote__c();
    newQuote.Name = 'Q-' + i;
    newQuote.SBQQ__Status__c = 'Draft';
    newQuote.SBQQ__ExpirationDate__c = Date.today().addDays(30);
    newQuote.SBQQ__TotalPrice__c = 5000 * i;  
    newQuote.SBQQ__CustomerDiscount__c = 5;
    
    quoteList.add(newQuote);
}

System.debug('10 SBQQ__Quote__c Records Created');
System.debug('Quote List: ' + quoteList);
System.debug('Total Quotes in List: ' + quoteList.size());


// Using the same instances of records you created in the first exercise, 
// print out at least one field you populated on each of the 10 sObjects

System.debug('3: Printing Specific Fields from Each sObject');

// 1. Account - Print Name
System.debug('1. Account Name: ' + acc.Name);

// 2. Opportunity - Print Name
System.debug('2. Opportunity Name: ' + opp.Name);

// 3. Opportunity Product (OpportunityLineItem) - Print Description
System.debug('3. Opportunity Product Description: ' + oppLineItem.Description);

// 4. CPQ Quote (SBQQ__Quote__c) - Print Status
System.debug('4. CPQ Quote Status: ' + cpqQuote.SBQQ__Status__c);

// 5. CPQ Quote Line (SBQQ__QuoteLine__c) - Print Quantity
System.debug('5. CPQ Quote Line Quantity: ' + quoteLine.SBQQ__Quantity__c);

// 6. Contact - Print Email
System.debug('6. Contact Email: ' + con.Email);

// 7. Order - Print Status
System.debug('7. Order Status: ' + ord.Status);

// 8. Order Item (OrderItem) - Print UnitPrice
System.debug('8. Order Item Unit Price: ' + ordItem.UnitPrice);

// 9. Product (Product2) - Print Description
System.debug('9. Product Description: ' + prod.Description);

// 10. Task - Print Subject
System.debug('10. Task Subject: ' + tsk.Subject);


//finished

