/**
 * @description Test data factory shared by all the test classes (DRY).
 *              - The "create" methods build the records and insert them.
 *              - The "build" methods only build them in memory (no insert), so that
 *                each test decides when to insert them.
 */
@IsTest
public class TestDataFactory {

    /**
     * @description Creates and inserts an Account.
     * @return The inserted Account
     */
    public static Account createAccount() {
        Account acc = new Account();
        acc.Name = 'Test Account';
        insert acc;
        return acc;
    }

    /**
     * @description Creates and inserts an Opportunity in the given stage.
     * @param accountId Account of the Opportunity
     * @param stageName Stage (for example 'Prospecting' or 'Closed Won')
     * @return The inserted Opportunity
     */
    public static Opportunity createOpportunity( Id accountId, String stageName ) {
        Opportunity opp = new Opportunity();
        opp.Name = 'Test Opportunity ' + stageName;
        opp.AccountId = accountId;
        opp.StageName = stageName;
        opp.CloseDate = Date.today().addDays( 30 );
        insert opp;
        return opp;
    }

    /**
     * @description Creates and inserts an active Product2.
     * @return The inserted Product2
     */
    public static Product2 createProduct() {
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.IsActive = true;
        insert product;
        return product;
    }

    /**
     * @description Creates a Product2 and its price in the standard Pricebook.
     *              Test.getStandardPricebookId() gives us the standard Pricebook Id
     *              inside the test, without needing to see the real org data.
     * @return The inserted PricebookEntry
     */
    public static PricebookEntry createPricebookEntry() {
        Product2 product = createProduct();

        PricebookEntry pricebookEntry = new PricebookEntry();
        pricebookEntry.Pricebook2Id = Test.getStandardPricebookId();
        pricebookEntry.Product2Id = product.Id;
        pricebookEntry.UnitPrice = 100;
        pricebookEntry.IsActive = true;
        insert pricebookEntry;
        return pricebookEntry;
    }

    /**
     * @description Creates and inserts a Draft Contract (not activated).
     * @param accountId Account of the Contract
     * @return The inserted Contract
     */
    public static Contract createDraftContract( Id accountId ) {
        Contract draftContract = new Contract();
        draftContract.AccountId = accountId;
        draftContract.StartDate = Date.today();
        draftContract.ContractTerm = 12;
        draftContract.Status = 'Draft';
        insert draftContract;
        return draftContract;
    }

    /**
     * @description Creates and inserts a Draft Contract with the given start date and term.
     *              Salesforce calculates the end date (start + term in months - 1 day).
     *              With contractTerm = null the Contract has no end date (evergreen).
     * @param accountId    Account of the Contract
     * @param startDate    Start date
     * @param contractTerm Term in months (can be null)
     * @return The inserted Contract
     */
    public static Contract createContract( Id accountId, Date startDate, Integer contractTerm ) {
        Contract con = buildContracts( accountId, startDate, contractTerm, 1 )[0];
        insert con;
        return con;
    }

    /**
     * @description Builds Draft Contracts with the given start date and term. It does not insert them.
     *              Salesforce does not allow inserting a Contract that is already Activated: to
     *              activate it, it has to be inserted in Draft and then the Status updated.
     * @param accountId         Account of the Contracts
     * @param startDate         Start date
     * @param contractTerm      Term in months (can be null: evergreen)
     * @param numberOfContracts Number of Contracts to build
     * @return List of Contracts, not inserted
     */
    public static List<Contract> buildContracts( Id accountId, Date startDate, Integer contractTerm, Integer numberOfContracts ) {
        List<Contract> contractList = new List<Contract>();
        for ( Integer i = 0; i < numberOfContracts; i++ ) {
            Contract con = new Contract();
            con.AccountId = accountId;
            con.StartDate = startDate;
            con.ContractTerm = contractTerm;
            con.Status = 'Draft';
            contractList.add( con );
        }
        return contractList;
    }

    /**
     * @description Builds one Renewal Opportunity per Contract, like the ones CPQ creates
     *              (SBQQ__Renewal__c = true and SBQQ__RenewedContract__c = the Contract). It does not insert them.
     * @param accountId    Account of the Opportunities
     * @param contractList Contracts renewed by each Opportunity (already inserted)
     * @param stageName    Stage (CPQ creates them in 'Prospecting')
     * @return List of Opportunities, not inserted
     */
    public static List<Opportunity> buildRenewalOpportunities( Id accountId, List<Contract> contractList, String stageName ) {
        List<Opportunity> opportunityList = new List<Opportunity>();
        for ( Contract con : contractList ) {
            Opportunity opp = new Opportunity();
            opp.Name = 'Test Renewal Opportunity';
            opp.AccountId = accountId;
            opp.StageName = stageName;
            opp.CloseDate = Date.today().addDays( 30 );
            opp.SBQQ__Renewal__c = true;
            opp.SBQQ__RenewedContract__c = con.Id;
            opportunityList.add( opp );
        }
        return opportunityList;
    }

    /**
     * @description Builds CPQ Subscriptions on a Contract, without their own dates (they take the
     *              Contract dates, like the ones CPQ creates in this org). It does not insert them.
     * @param contractId            Contract of the Subscriptions (can be null)
     * @param productId             Product of the Subscriptions
     * @param numberOfSubscriptions Number of Subscriptions to build
     * @param quantity              Value of SBQQ__Quantity__c (negative for an Amendment decrease)
     * @return List of Subscriptions, not inserted
     */
    public static List<SBQQ__Subscription__c> buildSubscriptions( Id contractId, Id productId, Integer numberOfSubscriptions, Decimal quantity ) {
        List<SBQQ__Subscription__c> subscriptionList = new List<SBQQ__Subscription__c>();
        for ( Integer i = 0; i < numberOfSubscriptions; i++ ) {
            SBQQ__Subscription__c sub = new SBQQ__Subscription__c();
            sub.SBQQ__Contract__c = contractId;
            sub.SBQQ__Product__c = productId;
            sub.SBQQ__Quantity__c = quantity;
            subscriptionList.add( sub );
        }
        return subscriptionList;
    }

    /**
     * @description Builds Draft Orders with the given Price Calculation Status. It does not insert them.
     * @param accountId       Account of the Orders
     * @param numberOfOrders  Number of Orders to build
     * @param priceCalcStatus Value of SBQQ__PriceCalcStatus__c
     * @return List of Orders, not inserted
     */
    public static List<Order> buildOrders( Id accountId, Integer numberOfOrders, String priceCalcStatus ) {
        List<Order> orderList = new List<Order>();
        for ( Integer i = 0; i < numberOfOrders; i++ ) {
            Order ord = new Order();
            ord.AccountId = accountId;
            ord.EffectiveDate = Date.today();
            ord.Status = 'Draft';
            ord.Pricebook2Id = Test.getStandardPricebookId();
            ord.SBQQ__PriceCalcStatus__c = priceCalcStatus;
            orderList.add( ord );
        }
        return orderList;
    }

    /**
     * @description Builds CPQ Quotes with the given Status and expiration date. It does not insert them.
     *              The expiration date is a parameter so it can be told apart from the one
     *              our trigger calculates (today + 30), which matches the CPQ default.
     * @param accountId      Account of the Quotes
     * @param numberOfQuotes Number of Quotes to build
     * @param status         Value of SBQQ__Status__c
     * @param expirationDate Initial value of SBQQ__ExpirationDate__c
     * @return List of Quotes, not inserted
     */
    public static List<SBQQ__Quote__c> buildQuotes( Id accountId, Integer numberOfQuotes, String status, Date expirationDate ) {
        List<SBQQ__Quote__c> quoteList = new List<SBQQ__Quote__c>();
        for ( Integer i = 0; i < numberOfQuotes; i++ ) {
            SBQQ__Quote__c quote = new SBQQ__Quote__c();
            quote.SBQQ__Account__c = accountId;
            quote.SBQQ__Status__c = status;
            quote.SBQQ__ExpirationDate__c = expirationDate;
            quoteList.add( quote );
        }
        return quoteList;
    }

    /**
     * @description Builds CPQ Quote Lines on a Quote. It does not insert them.
     *              When they are inserted, CPQ recalculates the Quote's SBQQ__LineItemCount__c Roll-Up.
     * @param quoteId            Quote of the lines (already inserted)
     * @param productId          Product of the lines
     * @param numberOfQuoteLines Number of lines to build
     * @return List of Quote Lines, not inserted
     */
    public static List<SBQQ__QuoteLine__c> buildQuoteLines( Id quoteId, Id productId, Integer numberOfQuoteLines ) {
        List<SBQQ__QuoteLine__c> quoteLineList = new List<SBQQ__QuoteLine__c>();
        for ( Integer i = 0; i < numberOfQuoteLines; i++ ) {
            SBQQ__QuoteLine__c quoteLine = new SBQQ__QuoteLine__c();
            quoteLine.SBQQ__Quote__c = quoteId;
            quoteLine.SBQQ__Product__c = productId;
            quoteLine.SBQQ__Quantity__c = 1;
            quoteLineList.add( quoteLine );
        }
        return quoteLineList;
    }

    /**
     * @description Builds a CPQ Quote Document (the record created by "Generate Document -> Save")
     *              for a Quote. It does not insert it.
     * @param quoteId       Quote of the document (already inserted)
     * @param opportunityId Opportunity of the document (can be null)
     * @return Quote Document, not inserted
     */
    public static SBQQ__QuoteDocument__c buildQuoteDocument( Id quoteId, Id opportunityId ) {
        SBQQ__QuoteDocument__c quoteDocument = new SBQQ__QuoteDocument__c();
        quoteDocument.Name = 'Test Quote Document';
        quoteDocument.SBQQ__Quote__c = quoteId;
        quoteDocument.SBQQ__Opportunity__c = opportunityId;
        return quoteDocument;
    }

    /**
     * @description Builds one Order Product per Order. It does not insert them.
     *              The Orders must already be inserted (their Id is needed).
     * @param orderList      Orders that will get the product
     * @param pricebookEntry Price of the product to add
     * @return List of OrderItems, not inserted
     */
    public static List<OrderItem> buildOrderItems( List<Order> orderList, PricebookEntry pricebookEntry ) {
        List<OrderItem> orderItemList = new List<OrderItem>();
        for ( Order ord : orderList ) {
            OrderItem item = new OrderItem();
            item.OrderId = ord.Id;
            item.PricebookEntryId = pricebookEntry.Id;
            item.Quantity = 1;
            item.UnitPrice = pricebookEntry.UnitPrice;
            orderItemList.add( item );
        }
        return orderItemList;
    }
}
