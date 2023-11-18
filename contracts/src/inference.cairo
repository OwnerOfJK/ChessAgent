// Orion and ML stuff
use core::array::SpanTrait;
use core::array::ArrayTrait;
use orion::operators::tensor::{TensorTrait, FP16x16Tensor, Tensor, FP16x16TensorAdd};
use orion::operators::nn::{NNTrait, FP16x16NN};
use orion::numbers::{FP16x16, FixedTrait};

use sequential_1_dense_1_matmul_readvariableop_0::tensor as t1;
use sequential_1_dense_1_biasadd_readvariableop_0::tensor as t2;
use sequential_1_dense_2_matmul_readvariableop_0::tensor as t3;
use sequential_1_dense_2_biasadd_readvariableop_0::tensor as t4;
use sequential_1_dense_3_matmul_readvariableop_0::tensor as t5;
use sequential_1_dense_3_biasadd_readvariableop_0::tensor as t6;

const MOVE_PLAYER0: u8 = 0;
const MOVE_PLAYER1: u8 = 1;
const MOVE_EMPTY: u8 = 2;

fn predict(mut x: Tensor<FP16x16>) -> FP16x16 {
    // let two = FixedTrait::<FP16x16>::new_unscaled(2, false);
    // let mut x = Tensor {
    //     shape: array![9].span(),
    //     data: array![two, two, two, two, two, two, two, two, two].span()
    // };

    // DENSE 1
    x = TensorTrait::matmul(@x, @t1());
    x = x + t2();
    x = NNTrait::relu(@x);

    // DENSE 2
    x = TensorTrait::matmul(@x, @t3());
    x = x + t4();
    x = NNTrait::relu(@x);

    // DENSE 3
    x = TensorTrait::matmul(@x, @t5());
    x = x + t6();

    return *x.data.at(0);
}

// def legal_moves_generator(current_board_state,turn_monitor):
//     """Function that returns the set of all possible legal moves and resulting board states, 
//     for a given input board state and player

//     Args:
//     current_board_state: The current board state
//     turn_monitor: 1 if it's the player who places the mark 1's turn to play, 0 if its his opponent's turn

//     Returns:
//     legal_moves_dict: A dictionary of a list of possible next coordinate-resulting board state pairs
//     The resulting board state is flattened to 1 d array

//     """
//     legal_moves_dict={}
//     for i in range(current_board_state.shape[0]):
//         for j in range(current_board_state.shape[1]):
//             if current_board_state[i,j]==2:
//                 board_state_copy=current_board_state.copy()
//                 board_state_copy[i,j]=turn_monitor
//                 legal_moves_dict[(i,j)]=board_state_copy.flatten()
//     return legal_moves_dict
fn legal_moves_generator(current_board_state: Array<u8>, turn_monitor: u8) -> Array<Array<u8>> {
    let mut moves = ArrayTrait::new();
    let mut index = 0;
    loop {
        if index == 3 * 3 {
            break;
        }
        // loop body
        if *current_board_state.at(index) == MOVE_EMPTY {
            let board_state_copy = modify_array_at_index(
                @current_board_state, index, turn_monitor.into()
            );
            moves.append(board_state_copy);
        }
        let copy = modify_array_at_index(@current_board_state, 1, 2);
        // end of loop body
        index += 1;
    };
    moves
}

fn modify_array_at_index(array: @Array<u8>, index: u32, value: u8) -> Array<u8> {
    let l = array.len();
    let mut new_array = ArrayTrait::new();
    let mut i = 0;
    loop {
        if i >= l {
            break;
        }
        new_array.append(if i == index {
            value
        } else {
            *array.at(i)
        });
        i += 1;
    };
    new_array
}
// def move_selector(model,current_board_state,turn_monitor):
//     """Function that selects the next move to make from a set of possible legal moves

//     Args:
//     model: The Evaluator function to use to evaluate each possible next board state
//     turn_monitor: 1 if it's the player who places the mark 1's turn to play, 0 if its his opponent's turn

//     Returns:
//     selected_move: The numpy array coordinates where the player should place thier mark
//     new_board_state: The flattened new board state resulting from performing above selected move
//     score: The score that was assigned to the above selected_move by the Evaluator (model)

//     """
//     tracker={}
//     legal_moves_dict=legal_moves_generator(current_board_state,turn_monitor)
//     for legal_move_coord in legal_moves_dict:
//         score=model.predict(legal_moves_dict[legal_move_coord].reshape(1,9))
//         tracker[legal_move_coord]=score
//     selected_move=max(tracker, key=tracker.get)
//     new_board_state=legal_moves_dict[selected_move]
//     score=tracker[selected_move]
//     return selected_move,new_board_state,score

#[cfg(test)]
mod tests {
    use super::{MOVE_PLAYER0, MOVE_PLAYER1, MOVE_EMPTY};
    #[test]
    #[available_gas(2000000000000)]
    fn test_modify_array_at_index() {
        let arr = array![1, 2, 3];
        let new_arr = super::modify_array_at_index(@arr, 1, 5);
        assert(*new_arr.at(0) == 1, 'wrong value at index 0');
        assert(*new_arr.at(1) == 5, 'wrong value at index 1');
        assert(*new_arr.at(2) == 3, 'wrong value at index 2');
    }

    //fn legal_moves_generator(current_board_state: Array<u8>, turn_monitor: u8) -> Array<Array<u8>> {
    #[test]
    #[available_gas(2000000000000)]
    fn test_legal_moves_generator() {
        let board = array![
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
            MOVE_PLAYER1,
            MOVE_PLAYER0,
            MOVE_PLAYER0,
            MOVE_EMPTY,
            MOVE_PLAYER1,
        ];
        let moves = super::legal_moves_generator(board, MOVE_PLAYER0);

        assert(moves.len() == 2, 'wrong moves len');

        let move0 = moves.at(0);
        let move1 = moves.at(1);

        assert(*move0.at(0) == MOVE_PLAYER0, 'wrong value at move 0 index 0');
        assert(*move0.at(1) == MOVE_PLAYER0, 'wrong value at move 0 index 1');
        assert(*move0.at(2) == MOVE_PLAYER0, 'wrong value at move 0 index 2');
        assert(*move0.at(3) == MOVE_PLAYER1, 'wrong value at move 0 index 3');
        assert(*move0.at(4) == MOVE_PLAYER1, 'wrong value at move 0 index 4');
        assert(*move0.at(5) == MOVE_PLAYER0, 'wrong value at move 0 index 5');
        assert(*move0.at(6) == MOVE_PLAYER0, 'wrong value at move 0 index 6');
        assert(*move0.at(7) == MOVE_EMPTY,   'wrong value at move 0 index 7');
        assert(*move0.at(8) == MOVE_PLAYER1, 'wrong value at move 0 index 8');

        assert(*move1.at(0) == MOVE_PLAYER0, 'wrong value at move 1 index 0');
        assert(*move1.at(1) == MOVE_PLAYER0, 'wrong value at move 1 index 1');
        assert(*move1.at(2) == MOVE_EMPTY,   'wrong value at move 1 index 2');
        assert(*move1.at(3) == MOVE_PLAYER1, 'wrong value at move 1 index 3');
        assert(*move1.at(4) == MOVE_PLAYER1, 'wrong value at move 1 index 4');
        assert(*move1.at(5) == MOVE_PLAYER0, 'wrong value at move 1 index 5');
        assert(*move1.at(6) == MOVE_PLAYER0, 'wrong value at move 1 index 6');
        assert(*move1.at(7) == MOVE_PLAYER0, 'wrong value at move 1 index 7');
        assert(*move1.at(8) == MOVE_PLAYER1, 'wrong value at move 1 index 8');
    }
}