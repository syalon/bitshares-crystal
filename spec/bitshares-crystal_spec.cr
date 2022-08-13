require "./spec_helper"
require "crystal-secp256k1-zkp"

class TestTask < BitShares::Task
  def main
    puts "test task"
    sleep(2)
  end
end

client = BitShares::Client.new BitShares::Config.new.tap { |cfg| cfg.api_nodes = "ws://101.35.27.58:10099" }
client.wallet.import_password("xx", "xx")
begin
  # pp client.build { |tx|
  #   tx.add_operation :withdraw_permission_create, {
  #     fee:                      {amount: 0, asset_id: "1.3.0"},
  #     withdraw_from_account:    "1.2.23173",
  #     authorized_account:       "1.2.23363",
  #     withdrawal_limit:         {amount: 100_00000, asset_id: "1.3.0"},
  #     withdrawal_period_sec:    3_u32,
  #     periods_until_expiration: 3600*24*366,
  #     period_start_time:        Time.utc.to_unix + 10,
  #   }
  # }

  pp client.build { |tx|
    tx.add_operation :withdraw_permission_claim, {
      fee:                   {amount: 0, asset_id: "1.3.0"},
      withdraw_permission:   "1.12.136",
      withdraw_from_account: "1.2.23173",
      withdraw_to_account:   "1.2.23363",
      amount_to_withdraw:    {amount: 10_00000, asset_id: "1.3.0"},
    }
  }
rescue e : BitShares::ResponseError
  pp e.graphene_error_message
  pp e
end

exit

client = BitShares::Client.new BitShares::Config.new.tap { |cfg| cfg.switch_bts_mainnet! }

# client.wallet.import_key("")
# pp client.do_account_create(
#   registrar: "1.2.xx",
#   referrer: "1.2.xx",
#   referrer_percent: 0,
#   voting_account: "1.2.5",
#   name: "name",
#   owner_public_key: "",
#   active_public_key: "",
#   memo_public_key: "",
# )

client.loop_new_block(0.5) do |new_block_number|
  begin
    pp client.call_history("get_block_operation_history", [new_block_number])
  rescue e : BitShares::ResponseError
    pp e
  end
end

# client.wallet.clear
exit

describe BitShares do
  # it "test tx" do
  #   client = BitShares::Client.new BitShares::Config.new.tap { |cfg| cfg.switch_bts_testnet! }
  #   client.wallet.clear

  #   client.wallet.import_password("test2021", "123456")

  #   pp client.do_samet_fund_create("test2021", "1.3.0", 12000, 0.025)

  #   # => 闪电贷：借款&还款
  #   account = "test2021"
  #   fund = "1.20.6"
  #   pp client.build { |tx|
  #     tx.add_operation :samet_fund_borrow, client.make_samet_fund_borrow(account, fund, "1.3.0", 1300)
  #     tx.add_operation :samet_fund_repay, client.make_samet_fund_repay(account, fund, "1.3.0", 1300, 326)
  #   }

  #   exit
  # end

  it "test generate keys" do
    prikey = Secp256k1Zkp::PrivateKey.from_account_and_password("test2021", "123456", "active")
    prikey.to_public_key.to_wif("TEST").should eq("TEST82xxRmEvn79T7ej5NXT8G5nXMMdHDTMrhcAsV4zfK23MMU92ZK")
  end

  it "test serialize" do
    puts "------"

    op_data = {
      :fee              => {"amount" => 1, "asset_id" => "1.3.2"},
      :registrar        => "1.2.3",
      :referrer         => "1.2.3",
      :referrer_percent => 1,
      :name             => "testopdataname",
      :owner            => {
        :weight_threshold => 1,
        :account_auths    => [["1.2.9", 12], ["1.2.3339", 5], ["1.2.0", 10]] of Array(String | Int32),
        :key_auths        => [["TEST82xxRmEvn79T7ej5NXT8G5nXMMdHDTMrhcAsV4zfK23MMU92ZK", 1]],
        :address_auths    => [] of Array(String | Int32),
      },
      :active => {
        :weight_threshold => 1,
        :account_auths    => [] of Array(String | Int32),
        :key_auths        => [["TEST82xxRmEvn79T7ej5NXT8G5nXMMdHDTMrhcAsV4zfK23MMU92ZK", 1]],
        :address_auths    => [] of Array(String | Int32),
      },
      :options => {
        :memo_key       => "TEST82xxRmEvn79T7ej5NXT8G5nXMMdHDTMrhcAsV4zfK23MMU92ZK",
        :voting_account => "1.2.5",
        :num_witness    => 0,
        :num_committee  => 0,
        :votes          => ["1:2", "1:111", "2:3", "1:8"] of String,
      },
    }

    p! BitShares::Operations::OP_account_create.to_binary(op_data, "TEST")
    pp JSON.parse(BitShares::Operations::OP_account_create.to_json(op_data, "TEST").to_json)

    exit
  end

  it "app start" do
    BitShares::App.start { |app|
      p! itself
      p! app

      run_task(TestTask)
      run_task(TestTask)
    }
    puts "--- app start finish ---"
  end

  it "run task with block" do
    BitShares::App.run_task { |task|
      i = 0
      while i <= 3
        sleep(1)
        puts "run_task with block #{i}"
        i += 1
      end
    }
    puts "--- finish ---"
  end

  it "run task with task obj" do
    BitShares::App.run_task(TestTask)
    puts "--- finish ---"
  end
end
