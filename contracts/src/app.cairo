use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};


const APP_KEY: felt252 = 'tictactoe';
const APP_ICON: felt252 = 'U+1F4A3';
const GAME_MAX_DURATION: u64 = 20000;
const APP_MANIFEST: felt252 = 'BASE/manifests/tictactoe';
const GAME_GRIDSIZE: u64 = 3;


#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct TicTacToeGame {
    #[key]
    id: u32,
    player1: ContractAddress,
    started_time: u64,
    x: u64,
    y: u64,
    moves_left: u8
}

#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct TicTacToeGameField {
    #[key]
    x: u64,
    #[key]
    y: u64,
    id: u32,
    index: u8,
    state: u8
}


// TODO GameFieldElement struct for each field (since Core has no "data" field)

#[starknet::interface]
trait ITicTacToeActions<TContractState> {
    fn init(self: @TContractState);
    fn interact(self: @TContractState, default_params: DefaultParameters) -> felt252;
    fn play(self: @TContractState, default_params: DefaultParameters) -> felt252;
    fn check_winner(
        self: @TContractState, default_params: DefaultParameters, game_array: Array<u8>
    ) -> u8;
}

#[dojo::contract]
mod tictactoe_actions {
    use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};
    use super::ITicTacToeActions;
    use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
    use pixelaw::core::models::permissions::{Permission};
    use pixelaw::core::actions::{
        IActionsDispatcher as ICoreActionsDispatcher,
        IActionsDispatcherTrait as ICoreActionsDispatcherTrait
    };
    use super::{
        APP_KEY, APP_ICON, APP_MANIFEST, GAME_MAX_DURATION, TicTacToeGame, TicTacToeGameField,
        GAME_GRIDSIZE
    };
    use pixelaw::core::utils::{get_core_actions, Position, DefaultParameters};
    use pixelaw::core::models::registry::{App, AppName, CoreActionsAddress};
    use debug::PrintTrait;

    use tictactoe::inference::move_selector;
    use core::array::SpanTrait;
    use orion::operators::tensor::{TensorTrait, FP16x16Tensor, Tensor, FP16x16TensorAdd};
    use orion::operators::nn::{NNTrait, FP16x16NN};
    use orion::numbers::{FP16x16, FixedTrait};

    #[derive(Drop, starknet::Event)]
    struct GameOpened {
        game_id: u32,
        creator: ContractAddress
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameOpened: GameOpened
    }

    #[external(v0)]
    impl TicTacToeActionsImpl of ITicTacToeActions<ContractState> {
        fn init(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let core_actions = pixelaw::core::utils::get_core_actions(world);

            core_actions.update_app(APP_KEY, APP_ICON, APP_MANIFEST);
        }

        fn interact(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            let game_id = world.uuid();

            try_game_setup(
                world, core_actions, system, player, game_id, position, default_params.color
            );

            let game = TicTacToeGame {
                id: world.uuid(),
                player1: player,
                started_time: starknet::get_block_timestamp(),
                x: position.x,
                y: position.y,
                moves_left: 9
            };

            set!(world, (game));

            'done'
        }

        fn play(self: @ContractState, default_params: DefaultParameters) -> felt252 {
            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            // Load the Pixel that was clicked
            let mut pixel = get!(world, (position.x, position.y), (Pixel));

            // Ensure the clicked pixel is a TTT 
            assert(pixel.app == get_contract_address(), 'not a TTT app pixel');

            // And load the corresponding GameField
            let mut field = get!(world, (position.x, position.y), TicTacToeGameField);

            // Ensure this pixel was not already used for a move
            assert(field.state == 0, 'field already set');

            // Process the player's move
            field.state = 1;
            set!(world, (field));

            // Change the Pixel
            core_actions
                .update_pixel(
                    player,
                    get_contract_address(),
                    PixelUpdate {
                        x: position.x,
                        y: position.y,
                        color: Option::None,
                        alert: Option::None,
                        timestamp: Option::None,
                        text: Option::Some('U+0058'),
                        app: Option::None,
                        owner: Option::None,
                        action: Option::Some('none')
                    }
                );

            // And load the Game
            let mut game = get!(world, (field.id), TicTacToeGame);

            game.moves_left -= 1;
            set!(world, (game));

            // Get the origin pixel
            let origin_position = Position { x: game.x, y: game.y };

            // Determine the game state
            let mut statearray = determine_game_state(world, game.x, game.y);

            if game.moves_left == 0 {
                // Check if the game is done and determine winner
                if self.check_winner(default_params, statearray) == 1 {
                    'human wins'.print();
                }
                // TODO Handle winner
                return 'human wins';
            }

            // Get the AI move
            let ai_move_index = move_selector(statearray.clone(), 1);

            // Handle the AI move
            // Find the pixel belonging to the index returned 
            // index 0 means the top-left pixel 
            let ai_position = position_from(origin_position, ai_move_index);

            // Change the field
            let mut ai_field = get!(world, (ai_position.x, ai_position.y), TicTacToeGameField);
            ai_field.state = 2;
            set!(world, (ai_field));

            // Change the Pixel
            core_actions
                .update_pixel(
                    player,
                    get_contract_address(),
                    PixelUpdate {
                        x: position.x,
                        y: position.y,
                        color: Option::None,
                        alert: Option::None,
                        timestamp: Option::None,
                        text: Option::Some('U+004F'),
                        app: Option::None,
                        owner: Option::None,
                        action: Option::Some('none')
                    }
                );

            // Update the Game object
            game.moves_left -= 1;
            set!(world, (game));



            'done'
        }


        fn check_winner(
            self: @ContractState, default_params: DefaultParameters, game_array: Array<u8>
        ) -> u8 {
            let mut player1: u8 = 1;
            let mut result: u8 = 0;
            if *game_array.at(0) == player1
                && *game_array.at(1) == player1
                && *game_array.at(2) == player1 {
                result = 1;
            }
            result
        }
    }

    // For a given array index, give the appropriate position
    fn position_from(origin: Position, index: u32) -> Position {
        let mut result = origin.clone();
        result.x = result.x + ((index+1) / 3).into();
        result.y = result.y + ((index+1) % 3).into();
        result
    }

    fn determine_game_state(world: IWorldDispatcher, x: u64, y: u64) -> Array<u8> {
        let mut result = array![];
        let mut i: u64 = 0;
        let mut j: u64 = 0;
        loop {
            if i >= GAME_GRIDSIZE {
                break;
            }
            j = 0;
            loop {
                if j >= GAME_GRIDSIZE {
                    break;
                }

                let field = get!(world, (x + i, y + j), TicTacToeGameField);
                result.append(field.state);

                j += 1;
            };
            i += 1;
        };
        result
    }

    fn try_game_setup(
        world: IWorldDispatcher,
        core_actions: ICoreActionsDispatcher,
        system: ContractAddress,
        player: ContractAddress,
        game_id: u32,
        position: Position,
        color: u32
    ) {
        let mut x: u64 = 0;
        let mut y: u64 = 0;
        loop {
            if x >= GAME_GRIDSIZE {
                break;
            }
            y = 0;
            loop {
                if y >= GAME_GRIDSIZE {
                    break;
                }

                let pixel = get!(world, (position.x + x, position.y + y), Pixel);
                assert(pixel.owner.is_zero(), 'No 9 free pixels!');

                y += 1;
            };
            x += 1;
        };

        x = 0;
        y = 0;
        let mut index = 0;

        loop {
            if x >= GAME_GRIDSIZE {
                break;
            }
            y = 0;
            loop {
                if y >= GAME_GRIDSIZE {
                    break;
                }

                core_actions
                    .update_pixel(
                        player,
                        system,
                        PixelUpdate {
                            x: position.x + x,
                            y: position.y + y,
                            color: Option::Some(color),
                            alert: Option::None,
                            timestamp: Option::None,
                            text: Option::None,
                            app: Option::Some(system),
                            owner: Option::Some(player),
                            action: Option::Some('play'),
                        }
                    );

                set!(
                    world,
                    (TicTacToeGameField {
                        x: position.x + x, y: position.y + y, id: game_id, index, state: 0
                    })
                );

                index += 1;
                y += 1;
            };
            x += 1;
        };
    }
}
