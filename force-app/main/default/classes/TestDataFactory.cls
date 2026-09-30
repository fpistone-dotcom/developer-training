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
     * @description Crea un Product2 y su precio en el Pricebook estándar.
     *              Test.getStandardPricebookId() nos da el Id del Pricebook estándar
     *              dentro del test, sin necesidad de ver los datos reales del org.
     * @return El PricebookEntry insertado
     */
    public static PricebookEntry createPricebookEntry() {
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.IsActive = true;
        insert product;

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
