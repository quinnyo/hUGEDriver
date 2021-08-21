include "include/hardware.inc"
include "include/hUGE.inc"

add_a_to_r16: MACRO
    add \2
    ld \2, a
    adc \1
    sub \2
    ld \1, a
ENDM

;; Thanks PinoBatch!
sub_from_r16: MACRO ;; (high, low, value)
    ld a, \2
    sub \3
    ld \2, a
    sbc a  ; A = -1 if borrow or 0 if not
    add \1
    ld \1, a
ENDM

add_a_to_hl: MACRO
    add_a_to_r16 h, l
ENDM

add_a_to_de: MACRO
    add_a_to_r16 d, e
ENDM

ret_dont_call_playnote: MACRO
    pop hl
    pop af
    ld a, 6 ; How many bytes until the next channel's code
    add_a_to_hl
    jp hl
ENDM

add_a_ind_ret_hl: MACRO
    ld hl, \1
    add [hl]
    inc hl
    ld h, [hl]
    ld l, a
    adc h
    sub l
    ld h, a
ENDM

load_hl_ind: MACRO
    ld hl, \1
    ld a, [hl+]
    ld h, [hl]
    ld l, a
ENDM

load_de_ind: MACRO
    ld a, [\1]
    ld e, a
    ld a, [\1+1]
    ld d, a
ENDM

retMute: MACRO
    bit \1, a
    ret nz
ENDM

checkMute: MACRO
    ld a, [mute_channels]
    bit \1, a
    jr nz, \2
ENDM

loadShort: MACRO
    ld a, [\1]
    ld \3, a
    ld a, [\1 + 1]
    ld \2, a
ENDM

;; Maximum pattern length
PATTERN_LENGTH EQU 64
;; Amount to be shifted in order to skip a channel.
CHANNEL_SIZE_EXPONENT EQU 3

SECTION "Playback variables", WRAM0
;; active song descriptor
order_cnt: db
_start_song_descriptor_pointers:
order1: dw
order2: dw
order3: dw
order4: dw

duty_instruments: dw
wave_instruments: dw
noise_instruments: dw

routines: dw
waves: dw
_end_song_descriptor_pointers:

;; variables
pattern1: dw
pattern2: dw
pattern3: dw
pattern4: dw

ticks_per_row: db
_hUGE_current_wave::
current_wave: db

;; Everything between this and `_end_vars` is zero-initialized by `hUGE_init`
_start_vars:

mute_channels: db
current_order: db
next_order: db
row_break: db

temp_note_value: dw
row: db
tick: db
counter: db

channels:
;;;;;;;;;;;
;;Channel 1
;;;;;;;;;;;
channel1:
channel_period1: dw
toneporta_target1: dw
channel_note1: db
vibrato_tremolo_phase1: db
envelope1: db
highmask1: db

;;;;;;;;;;;
;;Channel 2
;;;;;;;;;;;
channel2:
channel_period2: dw
toneporta_target2: dw
channel_note2: db
vibrato_tremolo_phase2: db
envelope2: db
highmask2: db

;;;;;;;;;;;
;;Channel 3
;;;;;;;;;;;
channel3:
channel_period3: dw
toneporta_target3: dw
channel_note3: db
vibrato_tremolo_phase3: db
envelope3: db
highmask3: db

;;;;;;;;;;;
;;Channel 4
;;;;;;;;;;;
channel4:
channel_period4: dw
toneporta_target4: dw
channel_note4: db
vibrato_tremolo_phase4: db
envelope4: db
highmask4: db

_end_vars:

SECTION "Sound Driver", ROM0

_hUGE_init_banked::
    ld hl, sp+2+4
    jr continue_init
_hUGE_init::
    ld hl, sp+2
continue_init:
    push bc
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    call hUGE_init
    pop bc
    ret

_hUGE_mute_channel_banked::
    ld hl, sp+3+4
    jr continue_mute
_hUGE_mute_channel::
    ld hl, sp+3
continue_mute:
    push bc
    ld a, [hl-]
    and 1
    ld c, a
    ld b, [hl]
    call hUGE_mute_channel
    pop  bc
    ret

hUGE_mute_channel::
    ;; B: channel
    ;; C: enable flag
    ld e, $fe
    ld a, b
    or a
    jr z, .enable_cut
.enable_loop:
    sla c
    rlc e
    dec a
    jr nz, .enable_loop
.enable_cut:
    ld a, [mute_channels]
    and e
    or  c
    ld [mute_channels], a
    and c
    call nz, note_cut
    ret

_hUGE_set_position_banked::
    ld hl, sp+2+4
    jr continue_set_position
_hUGE_set_position::
    ld hl, sp+2
continue_set_position:
    push bc
    ld c, [hl]
    call hUGE_set_position
    pop  bc
    ret
    
hUGE_init::
    push hl
    if !DEF(PREVIEW_MODE)
    ;; Zero some ram
    ld c, _end_vars - _start_vars
    ld hl, _start_vars
    xor a
.fill_loop:
    ld [hl+], a
    dec c
    jr nz, .fill_loop
    ENDC

    ld a, %11110000
    ld [envelope1], a
    ld [envelope2], a

    ld a, 100
    ld [current_wave], a

    pop hl
    ld a, [hl+] ; tempo
    ld [ticks_per_row], a

    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
    ld a, [de]
    ld [order_cnt], a

    ld c, _end_song_descriptor_pointers - (_start_song_descriptor_pointers)
    ld de, order1

.copy_song_descriptor_loop:
    ld a, [hl+]
    ld [de], a
    inc de
    dec c
    jr nz, .copy_song_descriptor_loop

    ld a, [current_order]
    ld c, a ;; Current order index

    ;; Fall through into _refresh_patterns

_refresh_patterns:
    ;; Loads pattern registers with pointers to correct pattern based on
    ;; an order index

    ;; Call with c set to what order to load

IF DEF(PREVIEW_MODE)
    db $fc ; signal order update to tracker
ENDC

    ld hl, order1
    ld de, pattern1
    call .load_pattern

    ld hl, order2
    call .load_pattern

    ld hl, order3
    call .load_pattern

    ld hl, order4

.load_pattern:
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, c
    add_a_to_hl

    ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl]
    ld [de], a
    inc de
    ret

_load_note_data:
    ;; Call with:
    ;; Pattern pointer in BC

    ;; Stores instrument/effect code in B
    ;; Stores effect params in C
    ;; Stores note number in A
    ld a, [row]
    ld h, a
    ;; Multiply by 3 for the note value
    add h
    add h

    ld h, 0
    ld l, a
    add hl, bc ; HL now points at the 3rd byte of the note
    ld a, [hl+]
    ld b, [hl]
    inc hl
    ld c, [hl]
    ret

_lookup_note:
    ;; Call with:
    ;; Pattern pointer in BC
    ;; channel_noteX pointer in DE

    ;; Stores note period value in HL
    ;; Stores instrument/effect code in B
    ;; Stores effect params in C
    ;; Stores note number in the memory pointed to by DE
    call _load_note_data
    ld hl, 0

    ;; If the note we found is greater than LAST_NOTE, then it's not a valid note
    ;; and nothing needs to be updated.
    cp LAST_NOTE
    ret nc

    ;; Store the loaded note value in channel_noteX
    ld [de], a

_convert_note:
    ;; Call with:
    ;; Note number in A
    ;; Stores note period value in HL

    add a ;; double it to get index into hi/lo table
    add a, LOW(note_table)
    ld l, a
    adc a, HIGH(note_table)
    sub l
    ld h, a
    ld a, [hl+]
    ld h, [hl]
    ld l, a

    scf
    ret

_convert_ch4_note:
    ;; Call with:
    ;; Note number in A
    ;; Stores polynomial counter in A
    ;; Free: HL

    ;; Invert the order of the numbers
    add 192 ; (255 - 63)
    cpl

    ;; Thanks to RichardULZ for this formula
    ;; https://docs.google.com/spreadsheets/d/1O9OTAHgLk1SUt972w88uVHp44w7HKEbS/edit#gid=75028951
    ; if A > 7 then begin
    ;   B := (A-4) div 4;
    ;   C := (A mod 4)+4;
    ;   A := (C or (B shl 4))
    ; end;

    ; if A < 7 then return
    cp 7
    ret c

    ld h, a

    ; B := (A-4) div 4;
    sub 4
    srl a
    srl a
    ld l, a

    ; C := (A mod 4)+4;
    ld a, h
    and 3 ; mod 4
    add 4

    ; A := (C or (B shl 4))
    swap l
    or l
    ret

_update_channel:
    ;; Call with:
    ;; Highmask in A
    ;; Channel in B
    ;; Note tone in DE
    ld c, a
    ld a, [mute_channels]
    dec b
    jr z, .update_channel2
    dec b
    jr z, .update_channel3
    dec b
    jr z, .update_channel4

.update_channel1:
    retMute 0

    ld a, e
    ldh [rAUD1LOW], a
    ld a, d
    or c
    ldh [rAUD1HIGH], a
    ret
.update_channel2:
    retMute 1

    ld a, e
    ldh [rAUD2LOW], a
    ld a, d
    or c
    ldh [rAUD2HIGH], a
    ret
.update_channel3:
    retMute 2

    ld a, e
    ldh [rAUD3LOW], a
    ld a, d
    or c
    ldh [rAUD3HIGH], a
    ret
.update_channel4:
    retMute 3

    ld a, e
    call _convert_ch4_note
    ldh [rAUD4POLY], a
    xor a
    ldh [rAUD4GO], a
    ret

_play_note_routines:
    jr _playnote1
    jr _playnote2
    jr _playnote3
    jr _playnote4

_playnote1:
    ld a, [mute_channels]
    retMute 0

    ;; Play a note on channel 1 (square wave)
    ld a, [temp_note_value+1]
    ld [channel_period1], a
    ldh [rAUD1LOW], a

    ld a, [temp_note_value]
    ld [channel_period1+1], a

    ;; Get the highmask and apply it.
    ld hl, highmask1
    or [hl]
    ldh [rAUD1HIGH], a

    ret

_playnote2:
    ld a, [mute_channels]
    retMute 1

    ;; Play a note on channel 2 (square wave)
    ld a, [temp_note_value+1]
    ld [channel_period2], a
    ldh [rAUD2LOW], a

    ld a, [temp_note_value]
    ld [channel_period2+1], a

    ;; Get the highmask and apply it.
    ld hl, highmask2
    or [hl]
    ldh [rAUD2HIGH], a

    ret

_playnote3:
    ld a, [mute_channels]
    retMute 2

    ;; This fixes a gameboy hardware quirk, apparently.
    ;; The problem is emulated accurately in BGB.
    ;; https://gbdev.gg8.se/wiki/articles/Gameboy_sound_hardware
    xor a
    ldh [rAUD3ENA], a
    cpl
    ldh [rAUD3ENA], a

    ;; Play a note on channel 3 (waveform)
    ld a, [temp_note_value+1]
    ld [channel_period3], a
    ldh [rAUD3LOW], a

    ld a, [temp_note_value]
    ld [channel_period3+1], a

    ;; Get the highmask and apply it.
    ld hl, highmask3
    or [hl]
    ldh [rAUD3HIGH], a

    ret

_playnote4:
    ld a, [mute_channels]
    retMute 3

    ;; Play a "note" on channel 4 (noise)
    ld a, [temp_note_value]
    ld [channel_period4+1], a
    ldh [rAUD4POLY], a

    ;; Get the highmask and apply it.
    ld a, [highmask4]
    ldh [rAUD4GO], a

    ret

_doeffect:
    ;; Call with:
    ;; B: instrument nibble + effect type nibble
    ;; C: effect parameters
    ;; E: channel

    ;; free: A, D, H, L

    ;; Strip the instrument bits off leaving only effect code
    ld a, b
    and %00001111
    ;; Multiply by 2 to get offset into table
    add a, a

    add a, LOW(.jump)
    ld l, a
    adc a, HIGH(.jump)
    sub l
    ld h, a
    
    ld a, [hl+]
    ld h, [hl]
    ld l, a

    ld b, e
    ld a, [tick]
    or a ; We can return right off the bat if it's tick zero
    jp hl

.jump:
    ;; Jump table for effect
    dw fx_arpeggio                     ;0xy
    dw fx_porta_up                     ;1xy
    dw fx_porta_down                   ;2xy
    dw fx_toneporta                    ;3xy
    dw fx_vibrato                      ;4xy
    dw fx_set_master_volume            ;5xy ; global
    dw fx_call_routine                 ;6xy
    dw fx_note_delay                   ;7xy
    dw fx_set_pan                      ;8xy
    dw fx_set_duty                     ;9xy
    dw fx_vol_slide                    ;Axy
    dw fx_pos_jump                     ;Bxy ; global
    dw fx_set_volume                   ;Cxy
    dw fx_pattern_break                ;Dxy ; global
    dw fx_note_cut                     ;Exy
    dw fx_set_speed                    ;Fxy ; global

setup_channel_pointer:
    ;; Call with:
    ;; Channel value in B
    ;; Offset in D
    ;; Returns value in HL

    ld a, b
    REPT CHANNEL_SIZE_EXPONENT
        add a
    ENDR
    add d
    ld hl, channels
    add a, LOW(channels)
    ld l, a
    adc a, HIGH(channels)
    sub l
    ld h, a
    ret

fx_set_master_volume:
    ret nz
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Upper 4 bits contain volume for left, lower 4 bits for right
    ;; Format is ?LLL ?RRR where ? is just a random bit, since we don't use
    ;; the Vin

    ;; This can be used as a more fine grained control over channel 3's output,
    ;; if you pan it completely.

    ld a, c
    ldh [rAUDVOL], a
    ret

fx_call_routine:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Routines are 16 bytes. Shift left to multiply by 16, then
    ;; jump to that location.
    load_hl_ind routines
    ld a, c
    and $0f
    add a
    add_a_to_hl
    ld a, [hl+]
    ld h, [hl]
    ld l, a

    ld a, [tick]
    push af
    inc sp
    push bc
    or a ; set zero flag if tick 0 for compatibility
    call .call_hl
    add sp, 3
    ret

.call_hl:
    jp hl

fx_set_pan:
    ret nz

    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Pretty simple. The editor can create the correct value here without a bunch
    ;; of bit shifting manually.

    ld a, c
    ldh [rAUDTERM], a
    ret

fx_set_duty:
    ret nz

    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; $900 = 12.5%
    ;; $940 = 25%
    ;; $980 = 50%
    ;; $9C0 = 75%

    ld a, b
    or a
    ld a, [mute_channels]
    jr z, .chan1
.chan2:
    retMute 1
    ld a, c
    ldh [rAUD2LEN], a
    ret
.chan1:
    retMute 0
    ld a, c
    ldh [rAUD1LEN], a
    ret

fx_vol_slide:
    ret nz

    ;; This is really more of a "retrigger note with lower volume" effect and thus
    ;; isn't really that useful. Instrument envelopes should be used instead.
    ;; Might replace this effect with something different if a new effect is
    ;; ever needed.


    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Todo
    ;; check channel mute
    ld d, 1
    ld a, b
    or a
    jr z, .cont
.loop:
    sla d
    dec a
    jr nz, .loop
.cont:
    ld a, [mute_channels]
    and d
    ret nz

    ;; setup the up and down params
    ld a, c
    and %00001111
    ld d, a

    ld a, c
    and %11110000
    ld e, a
    swap e

    ; There are 5 bytes between each envelope register
    ld a, b
    add a
    add a
    add b
    add LOW(rAUD1ENV)
    ld c, a

    ldh a, [c]
    and %11110000
    swap a
    sub d
    jr nc, .cont1
    xor a
.cont1:
    add e
    cp $10
    jr c, .cont2
    ld a, $F
.cont2:
    swap a
    ldh [c], a

    ; Go to rAUDxGO, which is 2 bytes after
    inc c
    inc c
    ldh a, [c]
    or %10000000
    ldh [c], a

    jr play_note

fx_note_delay:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    jr nz, .play_note

    ;; Just store the note into the channel period, and don't play a note.
    ld d, 0
    call setup_channel_pointer

    ld a, [temp_note_value+1]
    ld [hl+], a
    ld a, [temp_note_value]
    ld [hl], a

    ;; Don't call _playnote. This is done by grabbing the return
    ;; address and manually skipping the next call instruction.
    ret_dont_call_playnote

.play_note:
    cp c
    ret nz ; wait until the correct tick to play the note

play_note:
    ld d, 0
    call setup_channel_pointer

    ;; TODO: Change this to accept HL instead?
    ld a, [hl+]
    ld [temp_note_value+1], a
    ld a, [hl]
    ld [temp_note_value], a

    ;; TODO: Generalize this somehow?

    ld a, b
    add a
    add a, LOW(_play_note_routines)
    ld l, a
    adc a, HIGH(_play_note_routines)
    sub l
    ld h, a
    jp hl

fx_set_speed:
    ret nz

    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L
    ld a, c
    ld [ticks_per_row], a
    ret

hUGE_set_position::
fx_pos_jump:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld a, 1
    ld [row_break], a
    ld a, c
    ld [next_order], a

    ret

fx_pattern_break:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld a, c
    ld [row_break], a

    ret

fx_note_cut:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L
    cp c
    ret nz

    ;; check channel mute
    ld d, 1
    ld a, b
    or a
    jr z, .cont
.loop:
    sla d
    dec a
    jr nz, .loop
.cont:
    ld a, [mute_channels]
    and d
    ret nz

note_cut:
    ld hl, rAUD1ENV
    ld a, b
    add a
    add a
    add b ; multiply by 5
    add_a_to_hl
    ld [hl], 0
    ld a, b
    cp 2
    ret z ; return early if CH3-- no need to retrigger note

    ;; Retrigger note
    inc hl
    inc hl
    ld [hl], %11111111
    ret

fx_set_volume:
    ret nz ;; Return if we're not on tick zero.

    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Arguments to this effect will be massaged to correct form for the channel
    ;; in the editor so we don't have to AND and SWAP and stuff.

set_channel_volume:
    ;; Call with:
    ;; Correct volume value in C
    ;; Channel number in B

    ld a, [mute_channels]
    dec b
    jr z, .set_chn_2_vol
    dec b 
    jr z, .set_chn_3_vol
    dec b
    jr z, .set_chn_4_vol

.set_chn_1_vol:
    retMute 0

    ldh a, [rAUD1ENV]
    and %00001111
    swap c
    or c
    ldh [rAUD1ENV], a
    ret
.set_chn_2_vol:
    retMute 1

    ldh a, [rAUD2ENV]
    and %00001111
    swap c
    or c
    ldh [rAUD2ENV], a
    ret
.set_chn_3_vol:
    retMute 2

    ;; "Quantize" the more finely grained volume control down to one of 4 values.
    ld a, c
    cp 10
    jr nc, .one
    cp 5
    jr nc, .two
    or a
    jr z, .zero
.three:
    ld a, %01100000
    jr .done
.two:
    ld a, %01000000
    jr .done
.one:
    ld a, %00100000
    jr .done
.zero:
    xor a
.done:
    ldh [rAUD3LEVEL], a
    ret
.set_chn_4_vol:
    retMute 3

    swap c
    ld a, c
    ldh [rAUD4ENV], a
    ret

fx_vibrato:
    ret z
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ;; Extremely poor man's vibrato.
    ;; Speed values:
    ;; (0x0  = 1.0)
    ;; (0x1  = 0.5)
    ;; (0x3  = 0.25)
    ;; (0x7  = 0.125)
    ;; (0xf  = 0.0625)
    ld d, 4
    call setup_channel_pointer

    ld a, c
    and %11110000
    swap a
    ld e, a

    ld a, [counter]
    and e
    ld a, [hl]
    jr z, .go_up
.restore:
    call _convert_note
    jr .finish_vibrato
.go_up:
    call _convert_note
    ld a, c
    and %00001111
    add_a_to_hl
.finish_vibrato:
    ld d, h
    ld e, l
    xor a
    jp _update_channel

fx_arpeggio:
    ret z
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld d, 4
    call setup_channel_pointer
    ld d, [hl]

    ld a, [tick]
    dec a

    ;; TODO: A crappy modulo, because it's not a multiple of four :(

    jr .test_greater_than_two
.greater_than_two:
    sub a, 3
.test_greater_than_two:
    cp 3
    jr nc, .greater_than_two

    ;; Multiply by 2 to get offset into table
    add a

    add a, LOW(.arp_options)
    ld l, a
    adc a, HIGH(.arp_options)
    sub l
    ld h, a
    jp hl

.arp_options:
    jr .set_arp1
    jr .set_arp2
.reset_arp:
    ld a, d
    jr .finish_skip_add
.set_arp2:
    ld a, c
    swap a
    jr .finish_arp
.set_arp1:
    ld a, c
.finish_arp:
    and %00001111
    add d
.finish_skip_add:
    call _convert_note
    ld d, h
    ld e, l
    xor a
    jp _update_channel

fx_porta_up:
    ret z
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld d, 0
    call setup_channel_pointer

    ld a, [hl+]
    ld e, a
    ld d, [hl]

    ld a, c
    add_a_to_de

.finish:
    ld a, d
    ld [hl-], a
    ld [hl], e

    xor a
    jp _update_channel

fx_porta_down:
    ret z
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld d, 0
    call setup_channel_pointer

    ld a, [hl+]
    ld e, a
    ld d, [hl]

    ld a, c
    sub_from_r16 d, e, c

    jr fx_porta_up.finish

fx_toneporta:
    jr nz, .do_toneporta

    ;; We're on tick zero, so just move the temp note value into the toneporta target.
    ld d, 2
    call setup_channel_pointer

    ;; If the note is nonexistent, then just return
    ld a, [temp_note_value+1]
    or a
    jr z, .return_skip

    ld [hl+], a
    ld a, [temp_note_value]
    ld [hl], a

    ;; Don't call _playnote. This is done by grabbing the return
    ;; address and manually skipping the next call instruction.
.return_skip:
    ret_dont_call_playnote

.do_toneporta:
    ;; A: tick
    ;; ZF: (tick == 0)
    ;; B: channel
    ;; C: effect parameters

    ;; free registers: A, D, E, H, L

    ld d, 0
    call setup_channel_pointer
    push hl

    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a

    ld a, [hl+]
    ld h, [hl]
    ld l, a

    ;; Comparing which direction to move the current value
    ;; TODO: Optimize this!!!!

    ;; Compare high byte
    ld a, h

    cp d
    jr c, .subtract ; target is less than the current period
    jr z, .high_byte_same
    jr .add
.high_byte_same:
    ld a, l
    cp e
    jr c, .subtract ; the target is less than the current period
    jr z, .done ; both nibbles are the same so no portamento
.add:
    ld a, c
    add_a_to_de

    ld a, h
    cp d
    jr c, .set_exact
    jr nz, .done
    ld a, l
    cp e
    jr c, .set_exact

    jr .done

.subtract:
    sub_from_r16 d, e, c

    bit 7, d ; check for overflow
    jr nz, .set_exact

    ld a, d
    cp h
    jr c, .set_exact
    jr nz, .done
    ld a, e
    cp l
    jr c, .set_exact

    jr .done
.set_exact:
    ld d, h
    ld e, l
.done:
    pop hl
    ld a, e
    ld [hli], a
    ld [hl], d

    ld a, 6
    add_a_to_hl
    ld a, [hl]
    res 7, [hl]
    jp _update_channel

;; TODO: Find some way to de-duplicate this code!
_setup_instrument_pointer_ch4:
    ;; Call with:
    ;; Instrument/High nibble of effect in B
    ;; Stores whether the instrument was real in the Z flag
    ;; Stores the instrument pointer in DE
    ld a, b
    and %11110000
    swap a
    ret z ; If there's no instrument, then return early.

    dec a ; Instrument 0 is "no instrument"
    add a
    jr _setup_instrument_pointer.finish
_setup_instrument_pointer:
    ;; Call with:
    ;; Instrument/High nibble of effect in B
    ;; Stores whether the instrument was real in the Z flag
    ;; Stores the instrument pointer in DE
    ld a, b
    and %11110000
    swap a
    ret z ; If there's no instrument, then return early.

    dec a ; Instrument 0 is "no instrument"
.finish:
    ;; Shift left twice to multiply by 4
    add a
    add a

    add_a_to_de

    rla ; reset the Z flag
    ret

_hUGE_dosound_banked::
_hUGE_dosound::
    ld a, [tick]
    or a
    jp nz, .process_effects

    ;; Note playback
    loadShort pattern1, b, c
    ld de, channel_note1
    call _lookup_note
    push af
    jr nc, .do_setvol1

    load_de_ind duty_instruments
    call _setup_instrument_pointer
    ld a, [highmask1]
    res 7, a ; Turn off the "initial" flag
    jr z, .write_mask1

    checkMute 0, .do_setvol1

    ld a, [de]
    inc de
    ldh [rAUD1SWEEP], a
    ld a, [de]
    inc de
    ldh [rAUD1LEN], a
    ld a, [de]
    ldh [rAUD1ENV], a
    inc de
    ld a, [de]

.write_mask1:
    ld [highmask1], a

.do_setvol1:
    ld a, h
    ld [temp_note_value], a
    ld a, l
    ld [temp_note_value+1], a

    ld e, 0
    call _doeffect

    pop af              ; 1 byte
    jr nc, .after_note1 ; 2 bytes
    call _playnote1     ; 3 bytes

.after_note1:
    ;; Note playback
    loadShort pattern2, b, c
    ld de, channel_note2
    call _lookup_note
    push af
    jr nc, .do_setvol2

    load_de_ind duty_instruments
    call _setup_instrument_pointer
    ld a, [highmask2]
    res 7, a ; Turn off the "initial" flag
    jr z, .write_mask2

    checkMute 1, .do_setvol2

    inc de
    ld a, [de]
    inc de
    ldh [rAUD2LEN], a
    ld a, [de]
    ldh [rAUD2ENV], a
    inc de
    ld a, [de]

.write_mask2:
    ld [highmask2], a

.do_setvol2:
    ld a, h
    ld [temp_note_value], a
    ld a, l
    ld [temp_note_value+1], a

    ld e, 1
    call _doeffect

    pop af              ; 1 byte
    jr nc, .after_note2 ; 2 bytes
    call _playnote2     ; 3 bytes

.after_note2:
    loadShort pattern3, b, c
    ld de, channel_note3
    call _lookup_note

    ld a, h
    ld [temp_note_value], a
    ld a, l
    ld [temp_note_value+1], a

    push af

    jr nc, .do_setvol3

    load_de_ind wave_instruments
    call _setup_instrument_pointer
    ld a, [highmask3]
    res 7, a ; Turn off the "initial" flag
    jr z, .write_mask3

    checkMute 2, .do_setvol3

    ld a, [de]
    inc de
    ldh [rAUD3LEN], a
    ld a, [de]
    inc de
    ldh [rAUD3LEVEL], a
    ld a, [de]
    inc de

    ;; Check to see if we need to copy a wave and then do so
    ld hl, current_wave
    cp [hl]
    jr z, .no_wave_copy
    ld [hl], a
    swap a
    add_a_ind_ret_hl waves

    xor a
    ldh [rAUD3ENA], a

_addr = _AUD3WAVERAM
    REPT 16
        ld a, [hl+]
        ldh [_addr], a
_addr = _addr + 1
    ENDR

    ld a, %10000000
    ldh [rAUD3ENA], a

.no_wave_copy:
    ld a, [de]

.write_mask3:
    ld [highmask3], a

.do_setvol3:
    ld e, 2
    call _doeffect

    pop af              ; 1 byte
    jr nc, .after_note3 ; 2 bytes
    call _playnote3     ; 3 bytes

.after_note3:
    loadShort pattern4, b, c
    call _load_note_data
    ld [channel_note4], a
    cp LAST_NOTE
    push af
    jr nc, .do_setvol4

    call _convert_ch4_note
    ld [temp_note_value], a

    ld de, 0
    call _setup_instrument_pointer

    ld a, [highmask4]
    res 7, a ; Turn off the "initial" flag
    jr z, .write_mask4

    checkMute 3, .do_setvol4

    load_hl_ind noise_instruments
    sla e
    add hl, de

    ld a, [hl+]
    ldh [rAUD4ENV], a

    ld a, [hl]
    and %00111111
    ldh [rAUD4LEN], a

    ld a, [temp_note_value]
    ld d, a
    ld a, [hl]
    and %10000000
    swap a
    or d
    ld [temp_note_value], a

    ld a, [hl]
    and %01000000
    or  %10000000
.write_mask4:
    ld [highmask4], a

.do_setvol4:
    ld e, 3
    call _doeffect

    pop af              ; 1 byte
    jr nc, .after_note4 ; 2 bytes
    call _playnote4     ; 3 bytes

.after_note4:
    ;; finally just update the tick/order/row values
    jp process_tick

.process_effects:
    ;; Only do effects if not on tick zero
    checkMute 0, .after_effect1

    loadShort pattern1, b, c
    call _load_note_data

    ld a, c
    or a
    jr z, .after_effect1

    ld e, 0
    call _doeffect      ; make sure we never return with ret_dont_call_playnote macro

.after_effect1:
    checkMute 1, .after_effect2

    loadShort pattern2, b, c
    call _load_note_data

    ld a, c
    or a
    jr z, .after_effect2

    ld e, 1
    call _doeffect      ; make sure we never return with ret_dont_call_playnote macro

.after_effect2:
    checkMute 2, .after_effect3

    loadShort pattern3, b, c
    call _load_note_data

    ld a, c
    or a
    jr z, .after_effect3

    ld e, 2
    call _doeffect      ; make sure we never return with ret_dont_call_playnote macro

.after_effect3:
    checkMute 3, .after_effect4

    loadShort pattern4, b, c
    call _load_note_data
    cp LAST_NOTE
    jr nc, .done_macro
    ld h, a

    load_de_ind noise_instruments
    call _setup_instrument_pointer_ch4
    jr z, .done_macro ; No instrument, thus no macro

    ld a, [tick]
    cp 7
    jr nc, .done_macro

    inc de
    push de
    push de

    add_a_to_de
    ld a, [de]
    add h
    call _convert_ch4_note
    ld d, a
    pop hl
    ld a, [hl]
    and %10000000
    swap a
    or d
    ldh [rAUD4POLY], a

    pop de
    ld a, [de]
    and %01000000
    ldh [rAUD4GO], a

.done_macro:
    ld a, c
    or a
    jr z, .after_effect4

    ld e, 3
    call _doeffect      ; make sure we never return with ret_dont_call_playnote macro

.after_effect4:

process_tick:
    ld hl, counter
    inc [hl]

    ld a, [ticks_per_row]
    ld b, a

    ld hl, tick
    ld a, [hl]
    inc a

    cp b
    jr z, _newrow

    ld [hl], a
    ret

_newrow:
    ;; Reset tick to 0
    ld [hl], 0

    ;; Check if we need to perform a row break or pattern break
    ld a, [row_break]
    or a
    jr z, .no_break

    ;; These are offset by one so we can check to see if they've
    ;; been modified
    dec a
    ld b, a

    ld hl, row_break
    xor a
    ld [hl-], a
    or [hl]     ; a = [next_order], zf = ([next_order] == 0)
    ld [hl], 0

    jr z, _neworder

    dec a
    add a ; multiply order by 2 (they are words)

    jr _update_current_order

.no_break:
    ;; Increment row.
    ld a, [row]
    inc a
    ld b, a
    cp PATTERN_LENGTH
    jr nz, _noreset

    ld b, 0
_neworder:
    ;; Increment order and change loaded patterns
    ld a, [order_cnt]
    ld c, a
    ld a, [current_order]
    add a, 2
    cp c
    jr nz, _update_current_order
    xor a
_update_current_order:
    ;; Call with:
    ;; A: The order to load
    ;; B: The row for the order to start on
    ld [current_order], a
    ld c, a
    call _refresh_patterns

_noreset:
    ld a, b
    ld [row], a

IF DEF(PREVIEW_MODE)
    db $fd ; signal row update to tracker
ENDC
    ret

note_table:
include "include/hUGE_note_table.inc"
