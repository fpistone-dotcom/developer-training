/*
Apex Basics Final Challenge
In this Challenge, we will practice creating new record data.

1.Create a new Apex Class called DataGenerator.

2. Create a new method in the DataGenerator class called createAccountRecords(). This method should return a List of Account records. In the createAccountRecords() method:
    i. Create 100 new Accounts with the following fields:
        a. Set the Annual Revenue to a random number between 1 and 1,000,000
        b. Set the Customer Priority based on the Annual Revenue:
            a. If the Annual Revenue is less than $250,000, set to "Low"
            b. If the Annual Revenue is between $250,000 and $500,000, set to "Medium"
            c. If the Annual Revenue is greater than $500,000, set to "High"
    ii. Return the newly created Account records to the createAccountRecords() method

3. Create a new method in the DataGenerator class called createOpportunityRecords(). This method should accept a List of Account records. In the createOpportunityRecords() method:
    i. For any Account passed to the method that has a Customer Priority of "High", create a child Opportunity record associated to the Account.
        a. StageName: Randomly set to one of the following values: Qualification, Needs Analysis, Closed Won or Closed Lost.
        b. OwnerId: Set to the Account record's CreatedById
        c. Name: Account record's Name plus the word "Opportunity"

4. Create a new method in the DataGenerator class called createData(). This method should:
    i. Call the createAccountRecords() method and store the returned List of Accounts in a new variable called newAccounts.
    ii. Call the createOpportunityRecords() method and pass in the newAccounts variable as the parameter.
*/

//Create a new Apex Class called DataGenerator.
public class DataGenerator {

    public static List<Account> createAccountRecords() {
        
        List<Account> accountList = new List<Account>();

        for (Integer i = 0; i < 100; i++) {

            Account acc = new Account();

            acc.Name = 'Account ' + i;
            acc.AnnualRevenue = Math.round(Math.random() * 1000000); 

            if (acc.AnnualRevenue < 250000) {
                acc.CustomerPriority__c = 'Low';
            } else if (acc.AnnualRevenue >= 250000 && acc.AnnualRevenue <= 500000) {
                acc.CustomerPriority__c = 'Medium';
            } else {
                acc.CustomerPriority__c = 'High';
            }
            accountList.add(acc);
        }
        
        insert accountList;

        accountList = [SELECT Id, Name, CustomerPriority__c, CreatedById FROM Account WHERE Id IN :accountList];
        
        return accountList;
    }

    public static void createOpportunityRecords(List<Account> accounts) {
        List<Opportunity> opportunityList = new List<Opportunity>();
        
        // Requirement 3.a: StageName: Randomly set to one of the following values: Qualification, Needs Analysis, Closed Won or Closed Lost.
        List<String> validStages = new List<String>{'Qualification', 'Needs Analysis', 'Closed Won', 'Closed Lost'};
        
        for (Account acc : accounts) {
            if (acc.CustomerPriority__c == 'High') {
                Opportunity opp = new Opportunity();
                
                // Requirement 3: For any Account passed to the method that has a Customer Priority of "High", create a child Opportunity record associated to the Account.
                opp.AccountId = acc.Id;
                
                // Requirement 3.a: Randomly set to one of the following values: Qualification, Needs Analysis, Closed Won or Closed Lost.
                Integer randomIndex = (Integer)(Math.random() * validStages.size());
                opp.StageName = validStages[randomIndex]; 
                
                // Requirement 3.b: OwnerId: Set to the Account record's CreatedById
                opp.OwnerId = acc.CreatedById;
                // Requirement 3.c: Name: Account record's Name plus the word "Opportunity"
                opp.Name = acc.Name + ' Opportunity';
                
                opp.CloseDate = Date.today().addDays(30);

                opportunityList.add(opp);
            }
        }
        
        // Insert Opportunity records to the database
        if (!opportunityList.isEmpty()) {
            insert opportunityList;
        }
    }

    public static void createData() {  
        List<Account> newAccounts = createAccountRecords();
        createOpportunityRecords(newAccounts);
    }

    // --- TEST UTILS: Métodos deterministas para Clases de Prueba (Challenge 3)
    public static Account createTestAccount(String name, String typeVal, String ratingVal, Boolean doInsert) {
        Account acc = new Account(
            Name = name,
            Type = typeVal,
            Rating = ratingVal
        );
        if (doInsert) insert acc;
        return acc;
    }

    public static Contact createTestContact(Id accountId, Boolean doInsert) {
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = accountId,
            MailingStreet = '123 Test St',
            MailingCity = 'Test City',
            MailingState = 'NY',
            MailingPostalCode = '10001',
            MailingCountry = 'USA'
        );
        if (doInsert) insert con;
        return con;
    }

    public static Opportunity createTestOpportunity(Id accountId, String stageName, Boolean doInsert) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opp',
            AccountId = accountId,
            StageName = stageName,
            CloseDate = Date.today().addDays(30)
        );
        if (doInsert) insert opp;
        return opp;
    }

    public static Quote__c createTestQuote(Id opportunityId, Id accountId, String status, Boolean doInsert) {
        Quote__c q = new Quote__c(
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Status__c = status
        );
        if (doInsert) insert q;
        return q;
    }
}