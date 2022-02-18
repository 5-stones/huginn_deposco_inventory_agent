class DeposcoClient
    @faraday
    @auth

    def initialize(faraday, auth)
        @faraday = faraday
        @auth = auth

        @faraday.basic_auth(@auth['username'], @auth['password'])
    end

    # Get request given a path on the deposco api
    def get_deposco_stock(sku, business_unit)
        path = "/ctrl/getRestfulATP?businessUnit=#{business_unit}&itemNumber=#{sku}"
        url = "http://#{@auth['site_prefix']}.deposco.com/integration/#{@auth['site_code'] + path}"
        header = { 'Accept' => 'application/json' }
        response = @faraday.get(url, nil, header)
        if response.status == 200
            response = response.body
            response = JSON.parse(response)
            # response[0] because response from this endpoint is an array and
            # because we are looking up by sku we will always get 1 item back
            result = {
                sku: response[0]['itemNumber'],
                quantity: response[0]["totalAvailableToPromise"].to_i,
            }
            return result
        else
            raise DeposcoAgentError.new(response.body, response.status)
        end
    end
end
