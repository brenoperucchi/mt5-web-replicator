# #!/usr/bin/env python

# # WS server example

# import asyncio
# import websockets

# async def hello(websocket, path):
#     # name = await websocket.recv()
#     # print(f"< {name}")

#     greeting = "Hello"

#     await websocket.send(greeting)
#     print(f"> {greeting}")

# start_server = websockets.serve(hello, "192.168.1.240", 8700)
# asyncio.get_event_loop().run_until_complete(start_server)
# asyncio.get_event_loop().run_forever()

#!/usr/bin/env python

import asyncio
import websockets

async def echo(websocket, path):
    async for message in websocket:
        await websocket.send(message)
        await websocket.send("test")

asyncio.get_event_loop().run_until_complete(
    websockets.serve(echo, '192.168.1.240', 8700))
asyncio.get_event_loop().run_forever()