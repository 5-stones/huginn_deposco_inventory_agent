require 'huginn_agent'

HuginnAgent.load 'huginn_deposco_inventory_agent/deposco_client'
HuginnAgent.load 'huginn_deposco_inventory_agent/deposco_agent_error'

HuginnAgent.register 'huginn_deposco_inventory_agent/deposco_inventory_agent'
