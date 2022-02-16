# frozen_string_literal: true

module Agents
    class DeposcoInventoryAgent < Agent
        include WebRequestConcern

        default_schedule '12h'

        can_dry_run!
        default_schedule 'never'

        description <<-MD
        Huginn agent for retrieving and/or updating inventory data in Deposco

        This agent provides two key functions (controlled by the) `fetch_inventory`
        option. When set to `true`, this agent expects to receive an array of SKUs
        to fetch inventory levels from the Deposco API. These SKUs can be provided
        as an array, or as a CSV string.

        In this case, the agent will return inventory numbers adjusted by the reserved
        inventory total. The goal is to provide largely realtime updates to stock levels
        even in cases where orders from an external eCommerce platform are not immediately
        imported into Deposco.

        When `fetch_inventory` is set to `false`, this agent expects to receive
        an array of adjustment objects to be passed to the inventory reservation
        endpoint.

        Due to how the inventory reservation feature functions (particularly regarding
        instant inventory), it is important that this agent be configured with
        contextually appropriate credentials associated with the client for whom inventory
        is being retrieved.

        ### **Options:**
        *  fetch_inventory  - Optional. If provided, it must be either `true` or `false`. Defaults to `true`
        *  site_code        - Required.
        *  site_prefix      - Required.
        *  username         - Required.
        *  password         - Required.
        *  business_unit    - Required. This is the code associated with the client for whome you want to fetch/update data
        *  output_mode      - Optional. If provided, it must be set to either `clean` or `merge`. Defaults to `clean`
        *  skus             - Required when `fetch_inventory` is `true`. Must be an array or CSV of SKUs.
        *  adjustments      - An array of adjustment objects to be passed to the inventory reservation endpoint

        **NOTE:** The adustments field should be formatted as follows:

        ```
        adjustments: [
          {
            itemNumber: {sku},
            value: {adjustment amount}
          },
          { ... }
        ]
        ```


        ### **Agent Payloads:**

        #### **Fetch Inventory Success Payload:**

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

        #### **Fetch Inventory Error Payload:**

        **NOTE:** An error payload in this case may not be a catastrophic failure.
        In most cases, it means that one or more of the products could not be found
        in Deposco, which may happen for newer products that have been added to the store,
        but are not yet present in the warehouse.

        The intention of this error payload is to return as much useful data as we can while
        also notifying users that an error has occurred. It's up to the end user to determine
        whether this event should terminate the associated scenario execution or if this clan
        be treated as a partial success.

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

        #### **Reserve Inventory Success Payload:**

        **NOTE:** The `FAILURE` status shown here is somewhat misleading. In some cases,
        the status on the response _data_ will be a `FAILURE`, but the request itself is
        still considered a success.

        This will generally happen when a request tries to release more inventory than is
        currently available. For example, the warehouse has 100 items on hand, but 10 items
        are currently reserved -- making the _available_ quantity 90 units.

        An adjustment value of -20 would attempt to set the available stock to 110 units (90 - -20),
        however, since there are only 100 units on hand, this results in an error status with a message
        such as:

        "Attempted to update item [{SKU}] reserved quantity to a negative value. Reservation set to 0."

        The response.status in this case is still 200.

        ```
        {
          ...,
          reservation_result: {
            "status": "{SUCCESS | FAILURE}",
            "requestObj": {
               "company": "{company name}",
               "adjustments": [
                   {
                       "itemNumber": "{some sku}",
                       "value": {quantity}
                   },
                   { ... }
               ]
            },
            "responseMsg": []
          }
          status: 200,
        }

        #### **Reserve Inventory Error Payload:**

        ```
        {
          ...,

          "company": "{company name}",
          "adjustments": [
            {
              "itemNumber": "{some sku}",
              "value": {quantity}
            },
            { ... }
          ],
          "error": {
            message: '{ some error message }'
          },
          status: {response status},
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

            if options.has_key?('fetch_inventory') && boolify(options['fetch_inventory']).nil?
              errors.add(:base, 'when provided, `fetch_inventory` must be either true or false')
            end

            if !options.has_key?('fetch_inventory') || boolify(options['fetch_inventory'])
              if !options['skus'].present?
                  errors.add(:base, "When `fetch_inventory` mode is enabled, `skus` is a required field")
              else
                unless (options['skus'].is_a?(Array) || options['skus'].is_a?(String))
                    errors.add(:base, "skus must be an array or a string")
                end
              end
            end

            if options.has_key?('fetch_inventory') && !boolify(options['fetch_inventory'])
              unless options['adjustments'].present?
                errors.add(:base, "When `fetch_inventory` mode is disabled, `adjustments` is a required field")
              end

              unless options['adjustments'].is_a?(Array) || options['adjustments'].is_a?(String)
                  errors.add(:base, "adjustments must be an array of adjustment objects or a string")
              end
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

            new_event = interpolated['output_mode'].to_s == 'merge' ? event.payload.dup : {}
            fetch_inventory = boolify(options['fetch_inventory']).nil? ? true : boolify(options['fetch_inventory'])

            if (fetch_inventory)
                skus = interpolated(event.payload)[:skus]
                if skus.is_a?(String)
                    skus = skus.split(',')
                end

                # Get deposco stock inventory
                data = fetch_product_inventory(client, skus, business_unit)
                deposco_stock = data[:deposco_stock]
                errors = data[:errors]

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
            else
                adjustments = interpolated(event.payload)[:adjustments]

                if adjustments.is_a?(Array)
                    reserve_product_inventory(client, business_unit, adjustments, new_event)
                else
                    create_event payload: new_event.merge(
                      adjustments: adjustments,
                      status: 500,
                      error: 'The interpolated `adjustments` field must be an array. If you are passing a key from an incoming payload, consider using `{key | as_object}`'
                    )
                end
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
                begin
                    item = deposco_client.get_deposco_stock(sku, business_unit)

                    if item.is_a?(Hash)
                        deposco_stock << (item)
                    else
                        errors.push({
                            'sku': sku,
                            'status_code': 404,
                            'message': item
                        })
                    end
                rescue Faraday::Error::ClientError => e
                    status = 500
                    if defined?(e.response_status)
                        status = e.response_status
                    end

                    errors.push({
                        'sku': sku,
                        'status_code': status,
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

        # Attempts to update the inventory reservation numbers with the provided `adjustments`
        # NOTE: passing an adjustment with a positive number will _reserve_ inventory,
        # while passing a negative number will _release_ inventory.
        def reserve_product_inventory(deposco_client, business_unit, adjustments, event)
            begin
              result = deposco_client.reserve_deposco_stock(business_unit, adjustments)

              create_event payload: event.merge(
                  status: 200,
                  rservation_result: result,
              )
            rescue Faraday::Error::ClientError => e
                status = 500
                if defined?(e.response_status)
                    status = e.response_status
                end

                create_event payload: event.merge(
                    adjustments: adjustments,
                    status: status,
                    error: e.message
                )
            rescue DeposcoAgentError => e
              create_event payload: event.merge(
                  adjustments: adjustments,
                  status: e.status_code,
                  error: e.message
              )
            rescue => e
              create_event payload: event.merge(
                  adjustments: adjustments,
                  status: 500,
                  error: e.message
              )
            end
        end
    end
end
