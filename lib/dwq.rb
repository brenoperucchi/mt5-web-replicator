# require 'pycall/import'
# include PyCall::Import
# PyCall.sys.path.append File.dirname(Rails.root.join('lib', 'DWX_ZeroMQ_Connector_v2_0_1_RC8.py'))

# PyCall.import_module('DWX_ZeroMQ_Connector_v2_0_1_RC8')

# pyfrom 'DWX_ZeroMQ_Connector_v2_0_1_RC8', import: :'DWX_ZeroMQ_Connector'

# zmq = DWX_ZeroMQ_Connector.new


require 'pycall/import'
include PyCall::Import
PyCall.sys.path.append File.dirname(Rails.root.join('lib/dwx/v2.0.1b/python/api/dwx/dwx', 'mq'))
PyCall.import_module('client')

pyfrom 'client', import: :'DwxZmqConnector'

zmq = DwxZmqConnector.new