import pdb
import os
import asyncio
from metaapi_cloud_sdk import MetaApi
from metaapi_cloud_sdk.clients.metaApi.tradeException import TradeException
from metaapi_cloud_sdk import SynchronizationListener


# Note: for information on how to use this example code please read https://metaapi.cloud/docs/client/usingCodeExamples


token = 'eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiJlMTUwMjBkM2Y5Njg3NDM4OGUyOGEyMWFiYWZiNDY2MiIsInBlcm1pc3Npb25zIjpbXSwidG9rZW5JZCI6IjIwMjEwMjEzIiwiaWF0IjoxNjE4ODAxNDIxLCJyZWFsVXNlcklkIjoiZTE1MDIwZDNmOTY4NzQzODhlMjhhMjFhYmFmYjQ2NjIifQ.EuwKxunjBTHbg6HtjcKme-RdVTt0J6K5jimhJINzhhYGOLBnd_3WNgzzCutjB-8QHzdPt8PJlvUFj9q5lTRhTqrQ5P2da5UQRdzDV3f1ZReo5M3RWLccdcoLHu8Bzj25FcYqH2I8NLOfhK25VcFt-93a_VS1PWxGnEd2RwmYNllzUa1LgxMsyIdzfZwy2qj3OqnDhqvav3H_QqKYaOcRIYEbc-MbRWikMt70PbSZh0PMBeimgPKzcdRbDB7ggi8lIKntkbxbDkTADcM65ITqwkkpPulSH8MvIfFDtfeszSOOJNVEqILsPVFHokr4X3tdlzRCJyKs2VOepP3n6DbpwwLU2p4OmtfOgDndi1joS8QTplnb7WYzA89_yEz5EsK_abhc1FAPVSkXiVQUyyZhoasrHL8LX-N1JEbWEaLFVZsN6GamB_1Yul4DdH67OJP9d4sVvzX1PTzuXTLWDlDwUa9Wkncaq-ptjUm1dBOgUg3o-gSyNZ6KkjNWqdhDvHE6T_m0TzTQXiMQTLSoNoDTpSRrjUrBLjyEmAJYMbxiLgCo3CIppvDAUO5PkVsLwSmxNRVAahCoBV3Sf6aQP1s4j4wU_YzLJFvOrC8R5R8nnVKHZG02cs1CRPB4cOi0bK5TqOxOzRMdvEU86J0QpASfN2miQZ06-3gYJcfi4HjCl3I'
accountId = '477e6b85-e17c-4a8b-9362-2a2c810fc1cd'



async def test_meta_api_synchronization():
    api = MetaApi(token)
    try:
        # Add test MetaTrader account
        account = await api.metatrader_account_api.get_account(accountId)
        print('Waiting for API server to connect to broker (may take couple of minutes)')
        await account.wait_connected()

        # connect to MetaApi API
        connection = await account.connect()

        # wait until terminal state synchronized to the local state
        print('Waiting for SDK to synchronize to terminal state (may take some time depending on your history size)')
        sync = await connection.wait_synchronized({'timeoutInSeconds': 600})

        # access local copy of terminal state
        # print('Testing terminal state access')
        # pdb.set_trace()
        # print(sync.on_synchronization_started)	
        terminal_state = connection.terminal_state
        print('connected:', terminal_state.connected)
        # print('connected to broker:', terminal_state.connected_to_broker)
        # print('account information:', terminal_state.account_information)
        # print('positions:', terminal_state.positions)
        # print('orders:', terminal_state.orders)
        # print('connected:', connection.get_history_orders_by_position(2005466534))
        # print('specifications:', terminal_state.specifications)
        # print('EURUSD specification:', terminal_state.specification('EURUSD'))
        # print('EURUSD price:', terminal_state.price('EURUSD'))

        historyStorage = connection.history_storage

        # both orderSynchronizationFinished and dealSynchronizationFinished
        # should be true once history synchronization have finished
        # now add the listener
        listener = SynchronizationListener()
        on_connected = await listener.on_connected(account, 1)
        synchronized = await listener.on_synchronization_started(account)
        deals = await listener.on_deal_synchronization_finished(account, synchronized)
        print(deals)
        # # trade
        # print('Submitting pending order')
        # try:
        #     result = await connection.create_limit_buy_order('GBPUSD', 0.07, 1.0, 0.9, 2.0,
        #                                                      {'comment': 'comm', 'clientId': 'TE_GBPUSD_7hyINWqAlE'})
        #     print('Trade successful, result code is ' + result['stringCode'])
        # except Exception as err:
        #     print('Trade failed with error:')
        #     print(api.format_error(err))

        # finally, undeploy account after the test
        # print('Undeploying MT5 account so that it does not consume any unwanted resources')
        # await account.undeploy()

    except Exception as err:
        print(api.format_error(err))

asyncio.run(test_meta_api_synchronization())




# import os
# import pdb
# import asyncio
# from metaapi_cloud_sdk import MetaApi
# from metaapi_cloud_sdk.clients.metaApi.tradeException import TradeException
# from datetime import datetime, timedelta

# # Note: for information on how to use this example code please read https://metaapi.cloud/docs/client/usingCodeExamples

# token = 'eyJhbGciOiJSUzUxMiIsInR5cCI6IkpXVCJ9.eyJfaWQiOiJlMTUwMjBkM2Y5Njg3NDM4OGUyOGEyMWFiYWZiNDY2MiIsInBlcm1pc3Npb25zIjpbXSwidG9rZW5JZCI6IjIwMjEwMjEzIiwiaWF0IjoxNjE4ODAxNDIxLCJyZWFsVXNlcklkIjoiZTE1MDIwZDNmOTY4NzQzODhlMjhhMjFhYmFmYjQ2NjIifQ.EuwKxunjBTHbg6HtjcKme-RdVTt0J6K5jimhJINzhhYGOLBnd_3WNgzzCutjB-8QHzdPt8PJlvUFj9q5lTRhTqrQ5P2da5UQRdzDV3f1ZReo5M3RWLccdcoLHu8Bzj25FcYqH2I8NLOfhK25VcFt-93a_VS1PWxGnEd2RwmYNllzUa1LgxMsyIdzfZwy2qj3OqnDhqvav3H_QqKYaOcRIYEbc-MbRWikMt70PbSZh0PMBeimgPKzcdRbDB7ggi8lIKntkbxbDkTADcM65ITqwkkpPulSH8MvIfFDtfeszSOOJNVEqILsPVFHokr4X3tdlzRCJyKs2VOepP3n6DbpwwLU2p4OmtfOgDndi1joS8QTplnb7WYzA89_yEz5EsK_abhc1FAPVSkXiVQUyyZhoasrHL8LX-N1JEbWEaLFVZsN6GamB_1Yul4DdH67OJP9d4sVvzX1PTzuXTLWDlDwUa9Wkncaq-ptjUm1dBOgUg3o-gSyNZ6KkjNWqdhDvHE6T_m0TzTQXiMQTLSoNoDTpSRrjUrBLjyEmAJYMbxiLgCo3CIppvDAUO5PkVsLwSmxNRVAahCoBV3Sf6aQP1s4j4wU_YzLJFvOrC8R5R8nnVKHZG02cs1CRPB4cOi0bK5TqOxOzRMdvEU86J0QpASfN2miQZ06-3gYJcfi4HjCl3I'
# accountId = '477e6b85-e17c-4a8b-9362-2a2c810fc1cd'


# def test_meta_api_synchronization(meta_attributes):
# 	api = MetaApi(token)
# 	account = api.metatrader_account_api.get_account(accountId)
# 	initial_state = account.state
# 	deployed_states = ['DEPLOYING', 'DEPLOYED']
# 	# if initial_state not in deployed_states:
# 	#     #  wait until account is deployed and connected to broker
# 	#     print('Deploying account')
# 	#     await account.deploy()

# 	# print('Waiting for API server to connect to broker (may take couple of minutes)')
# 	account.wait_connected()
# 	# connect to MetaApi API
# 	connection = account.connect()


