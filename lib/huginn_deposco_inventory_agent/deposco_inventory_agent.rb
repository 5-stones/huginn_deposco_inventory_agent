# frozen_string_literal: true

module Agents
    class DeposcoInventoryAgent < Agent
        include WebRequestConcern

        default_schedule '12h'

        can_dry_run!
        default_schedule 'never'

        description <<-MD
        Huginn agent for retrieving sane Deposco quantity data.

        The deposco api requires you to either get all of the products inventory
        or to get one at a time. This agent gets one products inventory at a time
        given a list of skus as an array or a string, rather than pulling all
        products from deposco every time.

        This agent takes reserved inventory into account and will return the
        ATP amount specifically (Which is the stock level minus any reserved
        inventory). It is important that this agent is configured with the proper
        context (specifically that we should be using a login for the specific
        client we're trying to pull data for).



        ### **Options:**
        *  site_code     - required
        *  site_prefix   - required
        *  username      - required
        *  password      - required
        *  business_unit - required
        *  output_mode   - not required ('clean' or 'merge', defaults to 'clean')
        *  skus          - required (string or array, defaults to string)


        ### **Agent Payloads:**

        **Success Payload:**

        ```
        {
          ...,
          deposco_stock: [
            {
              "sku": "TESTSKU",
              "quantity": 100
            }
          ],
          status: 200,
        }
        ```

        **Error Payload:**

        ```
        {
          ...,
          deposco_stock: [
            {
              "sku": "TESTSKU",
              "quantity": 100
            }
          ],
          status: 404,
          error: {
            "message": "SKU's not found in deposco.",
            "data": [
              "MISSING_SKU",
              ...
            ]
          }
        }
        ```

        MD

        def default_options
            {
                'site_code' => '',
                'site_prefix' => '',
                'username' => '',
                'password' => '',
                'business_unit' => '',
                'output_mode' => 'clean',
                'skus' => '',
            }
        end

        def validate_options
            unless options['site_code'].present?
                errors.add(:base, 'site_code is a required field')
            end

            unless options['site_prefix'].present?
                errors.add(:base, 'site_prefix is a required field')
            end

            unless options['username'].present?
                errors.add(:base, 'username is a required field')
            end

            unless options['password'].present?
                errors.add(:base, 'password is a required field')
            end

            unless options['business_unit'].present?
                errors.add(:base, 'business_unit is a required field')
            end

            if options['output_mode'].present? && !options['output_mode'].to_s.include?('{') && !%[clean merge].include?(options['output_mode'].to_s)
              errors.add(:base, "if provided, output_mode must be 'clean' or 'merge'")
            end

            unless options['skus'].present?
                errors.add(:base, "skus is a required field")
            end

            unless (options['skus'].is_a?(Array) || options['skus'].is_a?(String)) && !blank?
                errors.add(:base, "skus must be an array or a string")
            end
        end

        def working?
            received_event_without_error?
        end

        def check
            handle interpolated['payload'].presence || {}
        end

        def receive(incoming_events)
            incoming_events.each do |event|
                interpolate_with(event) do
                    handle event
                end
            end
        end

        private

        def handle(event = Event.new)
            # Process agent options
            site_code = interpolated(event.payload)[:site_code]
            site_prefix = interpolated(event.payload)[:site_prefix]
            username = interpolated(event.payload)[:username]
            password = interpolated(event.payload)[:password]
            business_unit = interpolated(event.payload)[:business_unit]
            skus = interpolated(event.payload)[:skus]
            if skus.is_a?(String)
                skus = skus.split(',')
            end

            # Configure the Deposco Client
            auth = {
                'username' => username,
                'password' => password,
                'site_code' => site_code,
                'site_prefix' => site_prefix,
            }

            client = DeposcoClient.new(faraday, auth)

            # Get deposco stock inventory
            data = fetch_product_inventory(client, skus, business_unit)
            deposco_stock = data[:deposco_stock]
            errors = data[:errors]

            new_event = interpolated['output_mode'].to_s == 'merge' ? event.payload.dup : {}

            if errors.blank?
                create_event payload: new_event.merge(
                    deposco_stock: deposco_stock,
                    status: 200
                )
            else
                create_event payload: new_event.merge(
                    deposco_stock: deposco_stock,
                    status: 500,
                    errors: errors
                )
            end
        end

        private


        # Returns an array with an object with a field name deposco_stock
        # and a field name of errors. errors consists of a sku and an error message
        # and deposco_stock consists of objects with a sku and a quantity.
        def fetch_product_inventory(deposco_client, skus, business_unit)
            deposco_stock = []
            errors = []

            skus.each do |sku|
                path = "/items/#{business_unit}/#{sku}/atps"

                begin
                    item = deposco_client.get_deposco_stock(path)

                    if item.is_a?(Hash)
                        deposco_stock.push(item)
                    else
                        errors.push({
                            'sku': sku,
                            'status_code': 404,
                            'message': item
                        })
                    end
                rescue Faraday::Error::ClientError => e
                    errors.push({
                        'sku': sku,
                        'status_code': e.response_status,
                        'message': e.message
                    })
                rescue DeposcoAgentError => e
                    errors.push({
                        'sku': sku,
                        'status_code': e.status_code,
                        'message': e.message
                    })
                rescue => e
                    errors.push({
                        'sku': sku,
                        'status_code': 500,
                        'message': e.message
                    })
                end
            end

            return {
                deposco_stock: deposco_stock,
                errors: errors
            }
        end
    end
end
