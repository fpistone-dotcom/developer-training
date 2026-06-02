//Requirement #1.15: Using Lists & Sets in Queries
//Query out all Opportunity records where the StageName is "Needs Analysis"
List<Opportunity> oppList = [
    SELECT Id, Name, AccountId 
    FROM Opportunity 
    WHERE StageName = 'Needs Analysis'
];

system.debug('Opportunities in Needs Analysis stage: ' + oppList);


//Using this List of Opportunities, create a Set of all the parent Account record Ids
Set<Id> accountIds = new Set<Id>();

for (Opportunity opp : oppList) {
    accountIds.add(opp.AccountId);
}
system.debug('Set of Account Ids: ' + accountIds);

//Using this Set of Ids, query out the Account records
List<Account> accounts = [
    SELECT Id, Name, Industry 
    FROM Account 
    WHERE Id IN :accountIds
];
System.debug('Accounts related to Opportunities in Needs Analysis stage: ' + accounts);

//Print out the Name and Industry fields of each Account returned in the previous step
for (Account acc : accounts) {
    system.debug('Account Name: ' + acc.Name + ', Industry: ' + acc.Industry);
}

//Query all Quote records associated to the Accounts returned in step 3
List<SBQQ__Quote__c> quotes = [
    SELECT Id, Name, SBQQ__Account__c 
    FROM SBQQ__Quote__c 
    WHERE SBQQ__Account__c IN :accountIds
];
System.debug('Quotes associated with the Accounts: ' + quotes);


//Requirement #1.16: Lookups & Subqueries
//Accomplish the following using a single SOQL query:
//Find all Opportunity records where the CloseDate is in the future
//Print out the Name, Description and CreatedDate fields of all the parent Account records
//Find all the child Opportunity Products associated to each Opportunity
//Find the Opportunity Product that has the highest Quantity and return the associated Opportunity record's Name

List<Opportunity> futureOpps = [

    SELECT Id, Name, CloseDate, Account.Name, Account.Description, Account.CreatedDate,
           (
            SELECT Id, Quantity 
            FROM OpportunityLineItems
            )
    FROM Opportunity 
    WHERE CloseDate > TODAY
    
];

Decimal highestQuantity = 0;
String oppNameWithHighestQuantity = 'No products found'; 

for (Opportunity opp : futureOpps) {
    
    if (opp.Account != null) {
        System.debug(
            'Parent Account Name: ' + opp.Account.Name + 
            ' Description: ' + opp.Account.Description + 
            ' CreatedDate: ' + opp.Account.CreatedDate
             );
    }
    
    for (OpportunityLineItem oppProduct : opp.OpportunityLineItems) {
        
        if (oppProduct.Quantity != null && oppProduct.Quantity > highestQuantity) {
            highestQuantity = oppProduct.Quantity;   // Actualizamos el récord
            oppNameWithHighestQuantity = opp.Name;   // Guardamos el nombre de la Opp asociada
        }
    }
}

System.debug('Oportunidad con el producto de mayor cantidad: ' + oppNameWithHighestQuantity);
System.debug('Cantidad máxima encontrada: ' + highestQuantity);



//Requirement #1.17: Queries & Maps
//Use the Map constructor to query out all Contact records that have a Birthdate populated
Map<Id, Contact> contactMap = new Map<Id, Contact>([
    SELECT Id, Name, Description, Type, Birthdate 
    FROM Contact 
    WHERE Birthdate != null
]);

//Use the Map constructor to query out all Account records where the Rating is "Hot"
Map<Id, Account> accountMap = new Map<Id, Account>([
    SELECT Id, Name, Rating 
    FROM Account 
    WHERE Rating = 'Hot'
]);

//Using only these 2 Maps, count the number of Contact records from step 1 that are related to the Accounts records from step 2 where the Account record's Description field is populated
Integer count = 0;

for (Contact contact : contactMap.values()) {
    if (contact.AccountId != null && accountMap.containsKey(contact.AccountId)){
        Account relatedAccount = accountMap.get(contact.AccountId);
        if (relatedAccount.Description != null) {
            count++;
        }
    }

}

//Query out all Opportunities associated with the Account records from step 2 where the Account record is also "Customer - Channel"
Set<Id> hotCustomerAccountIds = new Set<Id>();

for (Account acc : accountMap.values()) {
    if (acc.Type == 'Customer - Channel') {
        hotCustomerAccountIds.add(acc.Id);
    }
}   

List<Opportunity> hotCustomerOpps = [SELECT Id, Name FROM Opportunity WHERE AccountId IN :hotCustomerAccountIds];
System.debug('Opportunities associated with Hot Customer Accounts: ' + hotCustomerOpps);