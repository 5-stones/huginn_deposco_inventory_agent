class DeposcoClient
    @faraday
    @auth

    def initialize(faraday, auth)
        @faraday = faraday
        @auth = auth

        @faraday.basic_auth(@auth['username'], @auth['password'])
    end

    # Get request given a path on the deposco api
    def get_deposco_stock(path, header = { 'Accept' => 'application/json' })
        url = "http://#{@auth['site_prefix']}.deposco.com/integration/#{@auth['site_code'] + path}"
        response = @faraday.get(url, nil, header)
        if response.status == 200
            response = response.body
            response = JSON.parse(response)
            result = {
                sku: response['@itemNumber'],
                quantity: response["@availableToPromise"].to_i,
            }
            return result
        else
            raise DeposcoAgentError.new(response.body, response.status)
        end
    end
end
