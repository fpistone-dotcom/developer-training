/**
 * @description Fábrica de datos de prueba compartida por todas las test classes (DRY).
 *              - Los métodos "create" arman los registros y los insertan.
 *              - Los métodos "build" solo los arman en memoria (sin insert), para que
 *                cada test decida cuándo insertarlos.
 */
@IsTest
public class TestDataFactory {

    /**
     * @description Crea e inserta una Account.
     * @return La Account insertada
     */
    public static Account createAccount() {
        Account acc = new Account();
        acc.Name = 'Test Account';
        insert acc;
        return acc;
    }

    /**
     * @description Crea e inserta una Opportunity en la etapa indicada.
     * @param accountId Account de la Opportunity
     * @param stageName Etapa (por ejemplo 'Prospecting' o 'Closed Won')
     * @return La Opportunity insertada
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
     * @description Crea e inserta un Product2 activo.
     * @return El Product2 insertado
     */
    public static Product2 createProduct() {
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.IsActive = true;
        insert product;
        return product;
    }

    /**
     * @description Crea un Product2 y su precio en el Pricebook estándar.
     *              Test.getStandardPricebookId() nos da el Id del Pricebook estándar
     *              dentro del test, sin necesidad de ver los datos reales del org.
     * @return El PricebookEntry insertado
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
     * @description Crea e inserta un Contract en Draft (no activado).
     * @param accountId Account del Contract
     * @return El Contract insertado
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
     * @description Crea e inserta un Contract en Draft con el inicio y el plazo indicados.
     *              La fecha de fin la calcula Salesforce (inicio + plazo en meses - 1 día).
     *              Con contractTerm = null el Contract queda sin fecha de fin (evergreen).
     * @param accountId    Account del Contract
     * @param startDate    Fecha de inicio
     * @param contractTerm Plazo en meses (puede ser null)
     * @return El Contract insertado
     */
    public static Contract createContract( Id accountId, Date startDate, Integer contractTerm ) {
        Contract con = buildContracts( accountId, startDate, contractTerm, 1 )[0];
        insert con;
        return con;
    }

    /**
     * @description Arma Contracts en Draft con el inicio y el plazo indicados. No los inserta.
     *              Salesforce no deja insertar un Contract ya Activated: para activarlo hay que
     *              insertarlo en Draft y después hacer un update del Status.
     * @param accountId         Account de los Contracts
     * @param startDate         Fecha de inicio
     * @param contractTerm      Plazo en meses (puede ser null: evergreen)
     * @param numberOfContracts Cantidad de Contracts a armar
     * @return Lista de Contracts sin insertar
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
     * @description Arma una Renewal Opportunity por cada Contract, como las que crea CPQ
     *              (SBQQ__Renewal__c = true y SBQQ__RenewedContract__c = el Contract). No las inserta.
     * @param accountId    Account de las Opportunities
     * @param contractList Contracts que renueva cada Opportunity (ya insertados)
     * @param stageName    Etapa (CPQ las crea en 'Prospecting')
     * @return Lista de Opportunities sin insertar
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
     * @description Arma Subscriptions de CPQ en un Contract, sin fechas propias (toman las del
     *              Contract, como las que crea CPQ en este org). No las inserta.
     * @param contractId            Contract de las Subscriptions (puede ser null)
     * @param productId             Producto de las Subscriptions
     * @param numberOfSubscriptions Cantidad de Subscriptions a armar
     * @param quantity              Valor de SBQQ__Quantity__c (negativo para una baja de Amendment)
     * @return Lista de Subscriptions sin insertar
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
     * @description Arma Orders en Draft con el Price Calculation Status indicado. No las inserta.
     * @param accountId       Account de las Orders
     * @param numberOfOrders  Cantidad de Orders a armar
     * @param priceCalcStatus Valor de SBQQ__PriceCalcStatus__c
     * @return Lista de Orders sin insertar
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
     * @description Arma Quotes de CPQ con el Status y el vencimiento indicados. No las inserta.
     *              El vencimiento se recibe como parámetro para poder distinguirlo del que
     *              calcula nuestro trigger (hoy + 30), que coincide con el default de CPQ.
     * @param accountId      Account de las Quotes
     * @param numberOfQuotes Cantidad de Quotes a armar
     * @param status         Valor de SBQQ__Status__c
     * @param expirationDate Valor inicial de SBQQ__ExpirationDate__c
     * @return Lista de Quotes sin insertar
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
     * @description Arma un Order Product por cada Order. No los inserta.
     *              Las Orders ya tienen que estar insertadas (se necesita su Id).
     * @param orderList      Orders que van a recibir el producto
     * @param pricebookEntry Precio del producto a agregar
     * @return Lista de OrderItems sin insertar
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
