//Requirement #1.11: DML Practice
//Create 100 Account records using the insert statement
List<Account> testAccounts = new List<Account>();
for (Integer i = 0; i < 100; i++) {
    Account testAccount = new Account();
    testAccount.Name = 'Test Account ' + i;
    testAccounts.add(testAccount);
}
insert testAccounts;


//Using the Account records you just created, update the NumberOfEmployees field to a random number between 1 - 100
List<Account> accountsToUpdate = [SELECT Id, NumberOfEmployees FROM Account WHERE Name LIKE 'Test Account%'];
for (Account acc : accountsToUpdate) {
    acc.NumberOfEmployees = Integer.valueOf(Math.random() * 100); // Random number between 1 and 100
}
update accountsToUpdate;


//Using the same Account records, create a Set of Ids for all Account fields where the NumberOfEmployees field is even. Print out the size of this Set
Set<Id> evenEmployeeIds = new Set<Id>();
for (Account acc : accountsToUpdate) {
    if(acc.NumberOfEmployees % 2 == 0) {
        evenEmployeeIds.add(acc.Id);
    }
}
System.debug('Size of even employee IDs: ' + evenEmployeeIds.size());   

//Delete the Account records
delete accountsToUpdate;



//Requirement #1.12: Record Ids and Maps
//Create 5 Opportunity records
List<Opportunity> testOpportunities = new List<Opportunity>();
for (Integer i = 0; i < 5; i++) {
    Opportunity testOpportunity = new Opportunity();
    testOpportunity.Name = 'Test Opportunity ' + i;
    testOpportunity.CloseDate = Date.today().addDays(30);
    testOpportunity.StageName = 'Prospecting';
    testOpportunities.add(testOpportunity);
}
insert testOpportunities;


//Using the Opportunity records you just created, build a Set that holds the record Ids
Set<Id> opportunityIds = new Set<Id>();
for (Opportunity opp : [SELECT Id FROM Opportunity WHERE Name LIKE 'Test Opportunity%']) {
    opportunityIds.add(opp.Id);
}


//Using the Opportunity records you just created, build a Map where they key is the Opportunity record Id and the value is the Opportunity record
Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>();
for (Opportunity opp : [SELECT Id, Name FROM Opportunity WHERE Name LIKE 'Test Opportunity%']) {
    opportunityMap.put(opp.Id, opp);
}       


//Looping over the Set of Opportunity record Ids you created in step 2, use the get() method to find the related Opportunity record in the Map from step 3. 
//Print out the Opportunity record's Name.
for (Id oppId : opportunityIds) {
    Opportunity oppRecord = opportunityMap.get(oppId);
    System.debug('Opportunity Name: ' + oppRecord.Name);
}   


//Requirement #1.13: Building Relationships
//Create 5 Account records that have a Rating of "Hot"
List<Account> hotAccountList = new List<Account>();

for (Integer i = 0; i < 5; i++) {

    Account hotAccount = new Account();
    hotAccount.Name = 'Hot Account ' + i;
    hotAccount.Rating = 'Hot';

    hotAccountList.add(hotAccount);

}
insert hotAccountList;


//For each Account record, create 5 child Opportunity records that are related to the Account record. Set the StageName to "Needs Analysis"
List<Opportunity> opportunityList = new List<Opportunity>();

for (Account acc : hotAccountList) {

    for (Integer j = 0; j < 5; j++) {

        Opportunity opp = new Opportunity();
        opp.Name = 'Opportunity for ' + acc.Name + ' - ' + j;
        opp.AccountId = acc.Id; // Relate the Opportunity to the Account
        opp.StageName = 'Needs Analysis';
        opp.CloseDate = Date.today().addDays(30); // Set a Close Date for the Opportunity

        opportunityList.add(opp);

    }
}

insert opportunityList;

//For each Opportunity record, create 5 child Quote (SBQQ__Quote__c) records that are related to both the Opportunity and Account records
List<SBQQ__Quote__c> quoteList = new List<SBQQ__Quote__c>();

for (Opportunity opp : opportunityList) {

    for (Integer k = 0; k < 5; k++) {

        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        quote.Name = 'Quote for ' + opp.Name + ' - ' + k;
        quote.SBQQ__Opportunity__c = opp.Id; // Relate the Quote to the Opportunity
        quote.SBQQ__Account__c = opp.AccountId; // Relate the Quote to the Account

        quoteList.add(quote);

    }

}

insert quoteList;   

//Build a Map where the key is the Quote record Id and the value is a Set of record Ids - this Set should hold the parent Opportunity and Account record Ids
Map<Id, Set<Id>> quoteToParentIdsMap = new Map<Id, Set<Id>>();

for (SBQQ__Quote__c quote : quoteList) {

    Set<Id> parentIds = new Set<Id>(); 
    parentIds.add(quote.SBQQ__Opportunity__c); // Add Opportunity Id
    parentIds.add(quote.SBQQ__Account__c); // Add Account Id

    quoteToParentIdsMap.put(quote.Id, parentIds);

}  

//Print out the total number of Quote records in the Map
System.debug('Total number of Quote records in the Map: ' + quoteToParentIdsMap.keySet().size());



//Requirement #1.14: Database DML Methods
//Create 20 new Opportunity records where the Close Date is randomly set to a date 1-100 days in the future. Insert these records to the database.
List<Opportunity> futureOpportunities = new List<Opportunity>();

for (Integer i = 0; i < 20; i++) {

    Opportunity opp = new Opportunity();
    opp.Name = 'Future Opportunity ' + i;
    opp.CloseDate = Date.today().addDays(Integer.valueOf(Math.random() * 100) + 1); // Random Close Date between 1 and 100 days in the future
    opp.StageName = 'Prospecting';

    futureOpportunities.add(opp);

}

insert futureOpportunities;

//Loop through the inserted Opportunity records and if the Close Date is more than 30 days in the future, remove the value in the Stage Name field.
List<Opportunity> opportunitiesToUpdate = [SELECT Id, CloseDate, StageName FROM Opportunity WHERE Name LIKE 'Future Opportunity%'];

for (Opportunity opp : opportunitiesToUpdate) {

    if(opp.CloseDate > Date.today().addDays(30)) {
        opp.StageName = null; // Remove the value in the Stage Name field
    }

}       

//Using the Database.update method where the AllOrNone parameter is set to false, update the Opportunity records. Since the Stage Name is a required field, this should cause a DML error for some of the records. 
List<Database.SaveResult> updateResults = Database.update(opportunitiesToUpdate, false); 

//Using the Database.SaveResult and Database.Error methods, print out which records succeeded and which records failed. If a record failed, print out the error message.
for (Database.SaveResult result : updateResults) {

    if(result.isSuccess()) {
        System.debug('Record updated successfully with ID: ' + result.getId());
    } else {
        for(Database.Error error : result.getErrors()) {
            System.debug('Error for record: ' + error.getMessage() + ' - Status Code: ' + error.getStatusCode());
        }
    }

}

//finished