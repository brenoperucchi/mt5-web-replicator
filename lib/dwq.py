# # require 'pycall/import'
# # include PyCall::Import
# # PyCall.sys.path.append File.dirname(Rails.root.join('lib', 'DWX_ZeroMQ_Connector_v2_0_1_RC8.py'))
# PyCall.import_module('DWX_ZeroMQ_Connector_v2_0_1_RC8')

# pyfrom 'DWX_ZeroMQ_Connector_v2_0_1_RC8', import: :'DWX_ZeroMQ_Connector'

# dmq = DWX_ZeroMQ_Connector.new
import pdb
import os

#############################################################################
#############################################################################
_path = '/Users/brenoperucchi/Devs/telegram/lib'
os.chdir(_path)
#############################################################################
#############################################################################

from DWX_ZeroMQ_Connector_v2_0_1_RC8 import DWX_ZeroMQ_Connector
# from examples.template.modules.DWX_ZMQ_Execution import DWX_ZMQ_Execution
# from examples.template.modules.DWX_ZMQ_Reporting import DWX_ZMQ_Reporting
# pdb.set_trace()


_zmq = DWX_ZeroMQ_Connector()
_zmq._DWX_MTX_NEW_TRADE_()
_zmq._get_response_()