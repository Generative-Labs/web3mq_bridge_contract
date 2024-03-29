use starknet::ContractAddress;

#[starknet::interface]
trait IBridge<TContractState> {
    fn deposite(ref self: TContractState, target_chain_id: felt252, target_token_address: ContractAddress, src_token_address: ContractAddress, amount: u256, target_address: ContractAddress);
    fn append_support_chain_tokens(ref self: TContractState, target_chain_id: felt252, token_address: ContractAddress);
    fn remove_support_chain_tokens(ref self: TContractState, target_chain_id: felt252, token_address: ContractAddress);
    fn chain_tokens_support(self: @TContractState, target_chain_id: felt252, token_address: ContractAddress) -> bool;
    fn set_recipient_address(ref self: TContractState, recipient_address: ContractAddress);
    fn get_recipient_address(self: @TContractState) -> ContractAddress;
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn transferFrom(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
}

#[starknet::contract]
mod Web3mqBridge {
    // use snforge_std::PrintTrait;
    use openzeppelin::access::ownable::interface::IOwnable;
    use core::traits::TryInto;
    use core::option::OptionTrait;
    use core::array::SpanTrait;
    use core::array::ArrayTrait;
    use core::traits::Into;
    use core::box::BoxTrait;
    use core::starknet::event::EventEmitter;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;
    use starknet::ClassHash;
    use starknet::ContractAddress;
    use starknet::get_block_info;
    use starknet::get_contract_address;
    use starknet::{get_caller_address, get_tx_info};
    use web3mq_bridge_contract::bridge::{IERC20Dispatcher, IERC20DispatcherTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    /// Ownable
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    /// Upgradeable
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        support_chain_tokens: LegacyMap::<(felt252, ContractAddress), bool>,
		recipient_address: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        DepositeEvent: DepositeEvent
    }

    #[derive(Drop, starknet::Event)]
    struct DepositeEvent {
        caller: ContractAddress,
        src_chain_id: felt252,
        src_token_address: ContractAddress,
        target_chain_id: felt252,
        target_address: ContractAddress,
        amount: u256
        
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, recipient_address: ContractAddress) {
        self.ownable.initializer(owner);
        self.recipient_address.write(recipient_address);
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            // This function can only be called by the owner
            self.ownable.assert_only_owner();
            // Replace the class hash upgrading the contract
            self.upgradeable._upgrade(new_class_hash);
        }
    }

    #[external(v0)]
    impl Bridge of super::IBridge<ContractState> {
        fn deposite(ref self: ContractState, target_chain_id: felt252, target_token_address: ContractAddress, src_token_address: ContractAddress, amount: u256, target_address: ContractAddress){
            assert(self.support_chain_tokens.read((target_chain_id, target_token_address)), 'target token not support');
            assert(self.support_chain_tokens.read((get_tx_info().unbox().chain_id, src_token_address)), 'src token not support');
            let erc_20: IERC20Dispatcher = IERC20Dispatcher { contract_address: src_token_address };
            let caller = get_caller_address();
            erc_20.transferFrom(caller, self.recipient_address.read(), amount);
            self.emit(DepositeEvent{
                caller: caller,
                src_chain_id: get_tx_info().unbox().chain_id,
                src_token_address: src_token_address,
                target_chain_id: target_chain_id,
                target_address: target_address,
                amount: amount
            });
        }

		fn append_support_chain_tokens(ref self: ContractState, target_chain_id: felt252, token_address: ContractAddress){
            self.ownable.assert_only_owner();
            self.support_chain_tokens.write((target_chain_id, token_address), true);
        }

		fn remove_support_chain_tokens(ref self: ContractState, target_chain_id: felt252, token_address: ContractAddress){
            self.ownable.assert_only_owner();
            self.support_chain_tokens.write((target_chain_id, token_address), false);
        }

        fn chain_tokens_support(self: @ContractState, target_chain_id: felt252, token_address: ContractAddress) -> bool{
            return self.support_chain_tokens.read((target_chain_id, token_address));
        }

		fn set_recipient_address(ref self: ContractState, recipient_address: ContractAddress){
            self.ownable.assert_only_owner();
            self.recipient_address.write(recipient_address);
        }

        fn get_recipient_address(self: @ContractState) -> ContractAddress{
            return self.recipient_address.read();
        }
    }
}