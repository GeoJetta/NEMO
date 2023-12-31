# Sharp 64-Color Display Driver Notes

Sharp 64-Color Display(s) (currently I am only aware of the one) use a 6-bit parallel bus that has nothing in common with the monochrome SPI interface which is nicely laid out in a separate programming document. Since I found the datasheet on signals and timing tough to wrap my head around, some notes seemed appropriate to help at least myself if not others. Also, the seemingly unique way the display updates might reveal some code optimizations by understanding each piece.

## Protocol Basics

|Pin #  |Pin Name  |Function  |
|---------|---------|---------|
|1     |VDD2        |5V         |
|3     |GSP         |Gate (Vertical) Start?         |
|4     |GCK         |Gate Clock         |
|5     |GEN         |Gate Enable         |
|6     |INTB        |Gate/Binary Initial?  |
|7     |VB          |VCOM         |
|8     |VA          |VCOM Inverse         |
|9     |VDD1        |3.2V         |
|10    |VSS         |GND         |
|11    |BSP         |Binary (Horizontal) Start      |
|12    |BCK         |Binary Clock         |
|13    |R\[0]        |Red Odd         |
|14    |R\[1]        |Red Even         |
|15    |G\[0]        |Green Odd         |
|16    |G\[1]        |Green Even         |
|17    |B\[0]        |Blue Odd         |
|18    |B\[1]        |Blue Even         |
|20    |VCOM        |Alternating Square Wave Signal |

There are 18 used pins on the 21-pin display connector, of which 2 are power (5V/3.2V), 1 ground, and 3 reserved for VCOM and its equal and inverse signal counterparts VB and VA, respectively. We'll look at startup/shutdown sequence where these matter but for now they can be overlooked, with VCOM just being a consistent 60Hz(ish) square wave that in some way keeps the display running.

Besides the arbitrary VCOM signal things seem pretty normal so far. Since the module uses 2 bits per color and therefore 6bpp, you would intuitively expect the 6 parallel signals to represent a single pixel per cycle. And, you'd be ***very wrong***. Instead, at first each cycle provides half the information (MSB) for 2 horizontal pixels (even and odd, from e.g. R\[0] and R\[1]) at a time. Once half the color information for the whole line has been written, you send the other half (LSB) and then drop down a line and repeat. I'm guessing this seemingly strange way of writing to the display is down to the unique structure of the LCD, but maybe this is a common way to set things up for RGB parallel interfaces. Since the MSB controls 2/3 of each pixel and LSB 1/3, that gives 4 levels of color (2 bits each, 6bpp).

![Pixel Layout](image-5.png)

The display also allows for partial updating, essentially fast-forwarding through horizontal lines that don't need to be updated. In theory this means partial screen refresh rate could be faster than the 18Hz specified for the whole screen.

## Vertical Signal

The "outer loop" of updating each frame is in the vertical movement signaling as seen in the given strangely redundant figures. Each Gate Clock cycle is one horizontal line written to the display.

Looking at the clock/control signals here, the display update is first triggered when INTB has a rising edge (and it has a corresponding dip a half cycle before the display update ends). GSP fires for a full GCK cycle at the start of each new display update. Gate Enable (GEN) pulls high during each stable point in GCK.

At the 642nd GCK pulse (once all lines have been sent), everything goes stable for 6 cycles as seen in the figure.

![Vertical Signal Timing](image.png)

![Other Vertical Signal Timing](image-2.png)

## Horizontal Signal

Here we are zooming in on one single GCK cycle. The horizontal clock signal (BCK) is around 750kHz - faster than I would have thought but makes sense considering it ticks for every pixel (probably warranted more careful trace design for the prototype but we can always run it slower for now if it's an issue... something to keep in mind. Also an Nx748kHz oscillator might be helpful but we might be able to boost that from our LSO). Each full horizontal cycle delivers one period of MSB bits and another of LSB bits for the full line. Once we have that part in our minds, it's probably the simpler part of the protocol. Each BCK cycle moves over one pixel, with BSP triggered high at the start of each line for a period of a full BCK cycle.

![Horizontal Signal Timing](image-1.png)

![Other Horizontal Signal Timing](image-3.png)

## Partial Update

If we only want to update some of the horizontal lines, there's a protocol provided for skipping through faster vertically. To do that, we set all horizontal and vertical components inactive except for GCK which can traverse vertically at a maximum of 500kHz.

![Partial Update Signal Timing](image-4.png)

Expounding upon the note from earlier, according to what I can tell from the docs the partial frame update can happen a lot faster. Here's a rough estimate graph showing number of lines written to the display out of the total 320 vs. framerate. So under many conditions (writing text or pressing a button) where we're only writing a few lines, we can push the display to a much more user-friendly 30Hz+. This calculation lumps the intervals at the start and end of frame into the written frame timing so it overestimates framerate tending towards zero.

![Partial Update Framerate Estimate](image-9.png)
*Typo - X axis should read "# of **lines** written per frame"

## Pulling It All Together

There are a couple other things we have to keep in mind, mainly transitioning between commands and powering on/off.

![Mode Change Signal Timing](image-6.png)

## Startup Sequence

Some things to note are that the 5v supply must be turned on after the 3.2V one, and turned off before turning the lower voltage off. That can probably be handled in a safe easy way in Rust.

![Power On Sequence](image-7.png)

After >2 GCK cycles' time of being turned on has passed, an all black frame should be sent, and VCOM (preceded by VA) can start after 30 microseconds. After one full cycle, the display is in normal on mode.

## Power Off

Essentially the same sequence takes place in reverse, except we write the display black, then turn off VCOM and derivatives, then turn off power after 30 microseconds have passed. Will need to look into safe shutdown when battery/power is removed.

## Conclusion

These are most of the parts that I found confusing to grok from just going through the datasheet initially, and it's really just mostly assembling these few diagrams from that document. Of course, there are more details that should be found there like rise times that we'll have to look at more carefully.

## Software Implementation

- Initialize and shutdown should be automatically run at startup and shutdown.
- Framebuffer Size: 6bpp x 320 x 240 = 57.6kB
- Without lower level optimization, each pixel will likely be at least one byte (or four) - 76.8kB or an imposing 307.2kB framebuffer. Let's shoot for at least the former.

## Timing Events Table

At the finest timing grid resolution, all signal edges line up with a 3Mhz clock (or a tiny bit less, that's 333.3ns vs the recommended 335, but there is margin down to 330ns). This means we can just run a counter at this frequency and update edges at preprogrammed locations. I'll attempt to list all these events chronologically so that the FSM case statements are simply copy-paste constants.

### Horizontal Timing Table

|Cycle #  |Pin  |High/Low  | Constant Def |
|---------|---------|---------|---------|
|0        |INTB     |High     | FIRST_CYCLE = 0 |
|65 (>62) |GSP      |High     | GSP_CYC_1 = 65  |
|195 (>190)|GCK     |High (Toggle)     | GCK_CYC_1 = 195 |
|... | | | Missed a GCK cycle here. Add 248.
|196 |BSP     |High   | BSP_CYC_1 = GCK_CYC_1 + 1 |
|197 |BCK     |High   | BCK_CYC_1 = BSP_CYC_1 + 1 |
|198     |DATA        |DATA         | DATA_CYC_1 = BCK_CYC_1 + 1 |
|199     |BCK         |Low         | BCK_CYC_1d = BCK_CYC_1 + 2 |
|200     |DATA + BSP  |DATA + Low  | DATA_CYC_2 = DATA_CYC_1 + 2 = BSP_LOW |
|201     |BCK         |High         |
|202     |DATA        |DATA         |
|...     |...         |...         |
|246     |DATA + GEN  |DATA + High | GEN_CYC_H = GCK_CYC_1 + 51
|...     |...         |...         |
|323     |GSP  |Low | --Note: This is on second GCK cycle.
|...     |...         |...         |
|393     |DATA + GEN  |DATA + High | GEN_CYC_L = GCK_CYC_2 - 51
|...     |...         |...         |
|438     |DATA        |DATA     | LAST_DATA_CYC = DATA_CYC_1 + 240 |
|439     |BCK         |Low         |
|...     |...         |...         |
|443     |GCK         |High (Toggle)   | GCK_CYC_2 = GCK_CYC_1 + 248 Think I'm off by one somewhere here. |

### Vertical Timing Table

|GCK Cycle #  |Pin  |High/Low  | Constant Def |
|---------|---------|---------|---------|
|1.5        |GSP     |Low     |
|2        |GEN Start     |High     |
|641  | DATA Last
|642  |GEN Last
|646  |INTB | Low
|648  |Restart

## States

The display module really only has a few possible higher level states and distinct transitions between them.

Power Off -> Initialize (Black Frame) -> Hold -> Active

And the reverse.

During active frames, partial update can also happen which should be its own state.
