class DeposcoClient
    @faraday
    @auth

    @headers = {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }

    def initialize(faraday, auth)
        @faraday = faraday
        @auth = auth

        @faraday.basic_auth(@auth['username'], @auth['password'])
    end

    # Get request given a path on the deposco api
    def get_deposco_stock(sku, business_unit)
        path = "/ctrl/getRestfulATP?businessUnit=#{business_unit}&itemNumber=#{sku}"
        url = "http://#{@auth['site_prefix']}.deposco.com/integration/#{@auth['site_code'] + path}"
        response = @faraday.get(url, nil, @headers)
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

    # Make a POST call to the reserve inventory endpoint
    def reserve_deposco_stock( company, adjustments )

        body = {
          company: company,
          adjustments: adjustments
        }

        url = "https://#{@auth['site_prefix']}.deposco.com/integration/#{@auth['site_code']}/ctrl/reserveInventoryAPI"

        # NOTE:  By default, Faraday sends POST requests with a content type of `application/x-www-form-urlencoded`
        # In order to send JSON, we need to explicitly convert the hash.
        response = @faraday.post(url, body.to_json, @headers)

        if response.status == 200
            data = JSON.parse(response.body)

            if (data['status'] == 'SUCCESS')
              return data
            else
              #  NOTE:  The Reserve Inventory endpoint from Deposco returns some misleading
              #  status codes at times. For example, if they payload is incorrect, the endpoint
              #  returns a status of 200 with a message of "porcessed with no response" when we
              #  would expect something like a 422.
              #  A response from this endpoint is only truly successful if the _status_ on the
              #  response body is "SUCCESS"

              raise DeposcoAgentError.new(data, response.status != 200 ? response.status : 500)
            end
        else
            raise DeposcoAgentError.new(response.body, response.status)
        end
    end
end
