#include QMK_KEYBOARD_H

const uint16_t PROGMEM keymaps[][MATRIX_ROWS][MATRIX_COLS] = {

    /* Layer 0: Default macro keys (4 vertical 2U keys) */
    [0] = LAYOUT(
        C(S(KC_F13)),
        C(S(KC_F14)),
        C(S(KC_F15)),
        C(S(KC_F16))
    ),

    /* Layer 1: Configurable via Vial */
    [1] = LAYOUT(
        KC_TRNS,
        KC_TRNS,
        KC_TRNS,
        KC_TRNS
    ),

    /* Layer 2: Configurable via Vial */
    [2] = LAYOUT(
        KC_TRNS,
        KC_TRNS,
        KC_TRNS,
        KC_TRNS
    ),

    /* Layer 3: Configurable via Vial */
    [3] = LAYOUT(
        KC_TRNS,
        KC_TRNS,
        KC_TRNS,
        KC_TRNS
    )
};
