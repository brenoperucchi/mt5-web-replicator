import json  
import os
import asyncio
from metaapi_cloud_sdk import MetaApi
from metaapi_cloud_sdk.clients.metaApi.synchronizationListener import SynchronizationListener
from metaapi_cloud_sdk.metaApi.models import MetatraderSymbolPrice, MetatraderCandle, MetatraderTick, MetatraderBook, \
    MarketDataSubscription, MarketDataUnsubscription, MetatraderDeal
from typing import List

token = os.getenv('TOKEN') or 'eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiJlMTUwMjBkM2Y5Njg3NDM4OGUyOGEyMWFiYWZiNDY2MiIsInBlcm1pc3Npb25zIjpbXSwidG9rZW5JZCI6IjIwMjEwMjEzIiwiaWF0IjoxNjE5NzQwMzQ4LCJyZWFsVXNlcklkIjoiZTE1MDIwZDNmOTY4NzQzODhlMjhhMjFhYmFmYjQ2NjIifQ.lE5W-A77POtcIRMFB8OslwDUgLAq5tyCFONotIEQuTTA00ezT1Se66KFKGuavGLKk6W_d-ommNC40wiYmvblEsFl0u5O9hKZ0EIvJha6i7nGCXxAL9EPI2RhMc_czOOTutX-OnVMfitKHJN1IpCJVwaDpAZ9lDjcLfKCZisPbD_hP5zAvMy81gZeEbes7ms-VNYKFhqbgCAGIq_fKC6O0wpx_X-guHe-kVBqCr-lSxvVKbHkoDg2El246Xh9WT79hWGm3FnYjjPcfaO3jA5YEF1WZKKAO0oqnrNkf2ey9QTkKHtCtsWQEsohWsIopbULNe6DJ1B1bT-fPB08vBxgQP-Uh5kERSLdlR21XyjYAZ8p7Ujq8peVL1dtgrbfm5g-Q-I766Ibwac2Ie0X_nltiH1HWbNldAcdI0DUC4YG5Hb56EuwGHy-stW7oEsbCezdomoUAlyDfr056H-Er_kwnuk1OqfaJQF03-Jjwrqwlx2pMqFQBCqEdNd8h0sbPegOind-EORWIVlpLb4DGAkSPzVSWePGqtngDxnDfk7-IuLWLzU8TZiz7LciGMiugU4OGKYItFMA_CYkydBE_tW3MxggKlCxIEamY51pxyD6XXkvP0b2y7h4_3vJU_LF8AQVKeivdc9PWpSfJ1-Dnt16dNHqEsHLKiOGEY7tR3s1B6c'
account_id = os.getenv('ACCOUNT_ID') or 'b89a5fa2-6e9f-41b5-82f0-bd4d80f84f4e'
symbol = os.getenv('SYMBOL') or 'EURUSD'


def default(obj):
    """Default JSON serializer."""
    import calendar, datetime

    if isinstance(obj, datetime.datetime):
        if obj.utcoffset() is not None:
            obj = obj - obj.utcoffset()
        millis = int(
            calendar.timegm(obj.timetuple()) * 1000 +
            obj.microsecond / 1000
        )
        return millis
    raise TypeError('Not sure how to serialize %s' % (obj,))

class QuoteListener(SynchronizationListener):

    # async def on_symbol_price_updated(self, instance_index: int, price: MetatraderSymbolPrice):
    #     if price['symbol'] == symbol:
    #         print(symbol + ' price updated', price)

    async def on_deal_added(self, instance_index: int, deal: MetatraderDeal):
	    print('Deal:', deal)
	    print('Deal:', deal['entryType'])
	    if deal['entryType'] == 'DEAL_ENTRY_OUT':
	    	json_object = json.dumps(deal, default=default)  
	    	os.system("ruby -r '/Users/brenoperucchi/Devs/signalforex/lib/telegram/signal.rb' -e 'meta_get_open_positions("+json_object+")'")

    # async def on_candles_updated(self, instance_index: int, candles: List[MetatraderCandle], equity: float = None,
    #                              margin: float = None, free_margin: float = None, margin_level: float = None,
    #                              account_currency_exchange_rate: float = None):
    #     for candle in candles:
    #         if candle['symbol'] == symbol:
    #             print(symbol + ' candle updated', candle)

    # async def on_ticks_updated(self, instance_index: int, ticks: List[MetatraderTick], equity: float = None,
    #                            margin: float = None, free_margin: float = None, margin_level: float = None,
    #                            account_currency_exchange_rate: float = None):
    #     for tick in ticks:
    #         if tick['symbol'] == symbol:
    #             print(symbol + ' tick updated', tick)

    # async def on_books_updated(self, instance_index: int, books: List[MetatraderBook], equity: float = None,
    #                            margin: float = None, free_margin: float = None, margin_level: float = None,
    #                            account_currency_exchange_rate: float = None):
    #     for book in books:
    #         if book['symbol'] == symbol:
    #             print(symbol + ' order book updated', book)

    # async def on_subscription_downgraded(self, instance_index: int, symbol: str,
    #                                      updates: List[MarketDataSubscription] or None = None,
    #                                      unsubscriptions: List[MarketDataUnsubscription] or None = None):
    #     print('Market data subscriptions for ' + symbol + ' were downgraded by the server due to rate limits')


async def stream_quotes():
    api = MetaApi(token)
    try:
        account = await api.metatrader_account_api.get_account(account_id)

        #  wait until account is deployed and connected to broker
        print('Deploying account')
        if account.state != 'DEPLOYED':
            await account.deploy()
        else:
            print('Account already deployed')
        print('Waiting for API server to connect to broker (may take couple of minutes)')
        if account.connection_status != 'CONNECTED':
            await account.wait_connected()

        # connect to MetaApi API
        connection = await account.connect()

        quote_listener = QuoteListener()
        connection.add_synchronization_listener(quote_listener)

        # wait until terminal state synchronized to the local state
        print('Waiting for SDK to synchronize to terminal state (may take some time depending on your history size), the price streaming will start once synchronization finishes')
        await connection.wait_synchronized({'timeoutInSeconds': 1200})

        # Add symbol to MarketWatch if not yet added and subscribe to market data
        # Please note that currently only MT5 G1 instances support extended subscription management
        # Other instances will only stream quotes in response
        await connection.subscribe_to_market_data(symbol, [
            {'type': 'quotes', 'intervalInMilliseconds': 1000},
            {'type': 'candles', 'timeframe': '1m', 'intervalInMilliseconds': 10000},
            {'type': 'ticks'},
            {'type': 'marketDepth', 'intervalInMilliseconds': 1000}
        ])

        print('Streaming ' + symbol + ' market data now...')

        while True:
            await asyncio.sleep(1)

    except Exception as err:
        print(api.format_error(err))

asyncio.run(stream_quotes())