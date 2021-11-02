module BitShares
  module Blockchain
    enum ObjectType : Int8
      Null                =  0
      Base                =  1
      Account             =  2
      Asset               =  3
      Force_settlement    =  4
      Committee_member    =  5
      Witness             =  6
      Limit_order         =  7
      Call_order          =  8
      Custom              =  9
      Proposal            = 10
      Operation_history   = 11
      Withdraw_permission = 12
      Vesting_balance     = 13
      Worker              = 14
      Balance             = 15
      Htlc                = 16
      Custom_authority    = 17
      Ticket              = 18
      Liquidity_pool      = 19
      Samet_fund          = 20
      Credit_offer        = 21
      Credit_deal         = 22
    end

    ObjectTypeReverse = Hash(Int8, ObjectType).new.tap { |result| ObjectType.each { |k, v| result[v] = k } }

    enum ImplObjectType : Int8
      Global_property             =  0
      Dynamic_global_property     =  1
      Index_meta                  =  2
      Asset_dynamic_data          =  3
      Asset_bitasset_data         =  4
      Account_balance             =  5
      Account_statistics          =  6
      Transaction                 =  7
      Block_summary               =  8
      Account_transaction_history =  9
      Blinded_balance             = 10
      Chain_property              = 11
      Witness_schedule            = 12
      Budget_record               = 13
    end

    enum VoteType : Int8
      Committee = 0
      Witness   = 1
      Worker    = 2
    end

    enum Operations : Int8
      Transfer                                  =  0
      Limit_order_create                        =  1
      Limit_order_cancel                        =  2
      Call_order_update                         =  3
      Fill_order                                =  4
      Account_create                            =  5
      Account_update                            =  6
      Account_whitelist                         =  7
      Account_upgrade                           =  8
      Account_transfer                          =  9
      Asset_create                              = 10
      Asset_update                              = 11
      Asset_update_bitasset                     = 12
      Asset_update_feed_producers               = 13
      Asset_issue                               = 14
      Asset_reserve                             = 15
      Asset_fund_fee_pool                       = 16
      Asset_settle                              = 17
      Asset_global_settle                       = 18
      Asset_publish_feed                        = 19
      Witness_create                            = 20
      Witness_update                            = 21
      Proposal_create                           = 22
      Proposal_update                           = 23
      Proposal_delete                           = 24
      Withdraw_permission_create                = 25
      Withdraw_permission_update                = 26
      Withdraw_permission_claim                 = 27
      Withdraw_permission_delete                = 28
      Committee_member_create                   = 29
      Committee_member_update                   = 30
      Committee_member_update_global_parameters = 31
      Vesting_balance_create                    = 32
      Vesting_balance_withdraw                  = 33
      Worker_create                             = 34
      Custom                                    = 35
      Assert                                    = 36
      Balance_claim                             = 37
      Override_transfer                         = 38
      Transfer_to_blind                         = 39
      Blind_transfer                            = 40
      Transfer_from_blind                       = 41
      Asset_settle_cancel                       = 42
      Asset_claim_fees                          = 43
      Fba_distribute                            = 44
      Bid_collateral                            = 45
      Execute_bid                               = 46
      Asset_claim_pool                          = 47
      Asset_update_issuer                       = 48
      Htlc_create                               = 49
      Htlc_redeem                               = 50
      Htlc_redeemed                             = 51
      Htlc_extend                               = 52
      Htlc_refund                               = 53
      Custom_authority_create                   = 54
      Custom_authority_update                   = 55
      Custom_authority_delete                   = 56
      Ticket_create                             = 57
      Ticket_update                             = 58
      Liquidity_pool_create                     = 59
      Liquidity_pool_delete                     = 60
      Liquidity_pool_deposit                    = 61
      Liquidity_pool_withdraw                   = 62
      Liquidity_pool_exchange                   = 63
      Samet_fund_create                         = 64
      Samet_fund_delete                         = 65
      Samet_fund_update                         = 66
      Samet_fund_borrow                         = 67
      Samet_fund_repay                          = 68
      Credit_offer_create                       = 69
      Credit_offer_delete                       = 70
      Credit_offer_update                       = 71
      Credit_offer_accept                       = 72
      Credit_deal_repay                         = 73
      Credit_deal_expired                       = 74 # VIRTUAL
    end

    OperationsReverse = Hash(Int8, Operations).new.tap { |result| Operations.each { |k, v| result[v] = k } }
  end
end
