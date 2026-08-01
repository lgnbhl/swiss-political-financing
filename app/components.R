# components.R
# ---------------------------------------------------------------------------
# The design system and the reusable UI pieces.
#
# Colours come from the data-viz reference palette and were validated with its
# checker against this app's actual chart surface (white cards), not eyeballed:
#
#   node scripts/validate_palette.js "#2a78d6,#eb6834,#1baf7a,#eda100,#e87ba4,
#     #008300,#4a3aa7" --mode light --surface "#ffffff"
#   -> lightness band PASS · chroma floor PASS · CVD separation PASS (worst
#      adjacent 9.1) · normal-vision floor PASS (worst adjacent 19.6) ·
#      contrast WARN on three slots -> relief required.
#
# The contrast WARN is discharged by construction: every chart in this app sits
# on a page that also shows the same figures in a DataGrid, which is the "table
# view" relief the palette rule asks for.
#
# Categorical slots are assigned in fixed order and never cycled. Ranked bar
# charts are single-series and use slot 1 only -- colour follows the entity, so
# it must not track a bar's rank.
# ---------------------------------------------------------------------------

# ---- palette ----------------------------------------------------------------
SERIES <- c(
  "#2a78d6", # 1 blue
  "#eb6834", # 2 orange
  "#1baf7a", # 3 aqua
  "#eda100", # 4 yellow
  "#e87ba4", # 5 magenta
  "#008300", # 6 green
  "#4a3aa7"  # 7 violet
)

# The Yes-camp / No-camp comparison is the app's one genuinely polar encoding, so
# it does not use the categorical slots: it uses the documented diverging pair
# (blue vs red) as two ordinal ramps, darkest step first. Within a camp the
# contributors are ranked and take steps in order, so the largest sits at the
# base of the stack in the strongest step.
#
# Six steps over the ordinal-safe lightness range, validated as ramps rather than
# as a categorical set:
#
#   node scripts/validate_palette.js "<ramp>" --ordinal --mode light --surface "#ffffff"
#   CAMP_YES -> monotone PASS · ΔL PASS · light end #88b6f1 2.10:1 PASS · single hue PASS
#   CAMP_NO  -> monotone PASS · ΔL PASS · light end #fc8f87 2.23:1 PASS · single hue PASS
#   BUDGET   -> monotone PASS · ΔL PASS · light end #b2b2b2 2.12:1 PASS · single hue PASS
#
# and the two poles against each other as a 2-slot categorical:
#
#   node scripts/validate_palette.js "#246dc3,#c91c28" --mode light --surface "#ffffff" --pairs all
#   -> ALL PASS, worst pair CVD ΔE 24.1 (protan), normal-vision 32.3
#
# Six steps is also the cap on how many contributors are drawn separately: past
# five the rest fold into one "other" segment rather than cycling the ramp.
CAMP_YES <- c("#0d437f", "#1758a1", "#246dc3", "#3784e1", "#609dea", "#88b6f1")
CAMP_NO  <- c("#830011", "#a60b1c", "#c91c28", "#e9343a", "#f56661", "#fc8f87")
# Budgeted income is grey, always. The reader is here for what a campaign
# actually raised; the budget is the plan beside it, and a neutral ramp keeps it
# legible without competing for attention. Same six lightness steps, so a
# committee sits at the same height of its ramp in both bars:
#   BUDGET_RAMP -> monotone PASS · ΔL PASS · light end #b2b2b2 2.12:1 PASS
BUDGET_RAMP <- c("#444444", "#585858", "#6e6e6e", "#848484", "#9b9b9b", "#b2b2b2")

# The single step that stands for a whole camp (KPI accents, one-colour bars).
CAMP_POLE <- list(yes = CAMP_YES[3], no = CAMP_NO[3])

# Blue and red are the camp encoding, and only that: on this site blue means Yes
# / pour and red means No / contre. An informational callout takes neither side,
# so every note card carries the same neutral accent -- categorical slot 2 --
# rather than picking a colour per page. One accent also makes "this is a note,
# not a figure" learnable after the first page.
ACCENT_NOTE <- SERIES[2]   # orange

INK <- list(
  surface   = "#ffffff",   # card / chart surface
  plane     = "#f9f9f7",   # page plane
  bar       = "#1a1a19",   # app bar (dark chrome)
  primary   = "#0b0b0b",
  secondary = "#52514e",
  muted     = "#898781",   # axis + tick labels
  grid      = "#e1e0d9",   # hairline gridline
  baseline  = "#c3c2b7",
  border    = "rgba(11,11,11,0.10)",
  on_bar    = "#c3c2b7",   # nav text on the dark bar
  swiss_red = "#d52b1e"
)

# System sans everywhere, including figures -- no display face, and no webfont
# request, which keeps the built page fully self-contained.
FONT_STACK <- "system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif"

spf_theme <- function() {
  JS(sprintf("window.jsmodule['@mui/material'].createTheme({
    palette: {
      mode: 'light',
      primary:    { main: '%s' },
      background: { default: '%s', paper: '%s' },
      text:       { primary: '%s', secondary: '%s' },
      divider:    '%s'
    },
    shape: { borderRadius: 12 },
    typography: {
      fontFamily: \"%s\",
      h4:         { fontWeight: 700, letterSpacing: '-0.02em' },
      h5:         { fontWeight: 700, letterSpacing: '-0.01em' },
      h6:         { fontWeight: 600 },
      subtitle1:  { fontWeight: 600 },
      overline:   { fontWeight: 600, letterSpacing: '0.08em' }
    },
    components: {
      MuiCard:      { defaultProps: { elevation: 0 } },
      MuiButton:    { defaultProps: { disableElevation: true },
                      styleOverrides: { root: { textTransform: 'none', fontWeight: 600 } } },
      MuiChip:      { styleOverrides: { root: { fontWeight: 500 } } }
    }
  })", SERIES[1], INK$plane, INK$surface, INK$primary, INK$secondary, INK$grid, FONT_STACK))
}

# ---- number formatters (client side) ---------------------------------------
# Swiss usage groups thousands with an apostrophe in German, French and Italian
# alike, so franc amounts are formatted identically in all three languages
# (CHF 923'857, not the fr-CH default CHF 923 857). Keeping one format also
# means a figure does not appear to change when the reader switches language.
CH_LOCALE <- "de-CH"

# Only the landing page still formats in R; every other chart and grid gets its
# formatters from `window.spf.fmt()` in the loader. `lang` is accepted so call
# sites read symmetrically with the localised text helpers, and so a genuinely
# language-dependent format could be introduced in one place later.
js_chf   <- function(lang) JS(sprintf(
  "(v) => v == null ? '' : 'CHF ' + Math.round(v).toLocaleString('%s')", CH_LOCALE))
# Abbreviated axis ticks so franc figures do not collide; tooltips show the
# full value.
js_short <- function(lang) JS(sprintf(
  "(v) => window.spf.fmt('%s').short(v)", lang))

# ---- cards ------------------------------------------------------------------
CARD_SX <- list(
  height = "100%",
  border = "1px solid",
  borderColor = "divider",
  borderRadius = 3,
  backgroundColor = INK$surface
)

# ---- responsive scale -------------------------------------------------------
# The content column, used by the app bar, the pages and the footer alike so the
# logo, the headings and the footer note all start on the same vertical line.
#
# "lg" (1200px), not "xl" (1536px): a paragraph has a readable line length
# whatever the window is, so at 1536px the text stopped a third of the way across
# and the page read as half empty. Narrowing the column makes the same measure
# fill it.
SHELL_WIDTH <- "lg"

# The tree is built once in R and rendered statically, so there is no
# useMediaQuery and no state: every size that has to change with the viewport is
# an sx breakpoint object (or a rule in app_css()). `xs` is the phone, `md` the
# desktop; MUI fills in everything between.
#
# Card padding is the one that pays off everywhere -- MUI's default 16/24px
# gutter costs a fifth of a 360px screen once a card sits inside a Grid gap.
#
# Note the `&:last-child` override: CardContent ships `padding: 16px` with
# `&:last-child { padding-bottom: 24px }`, so a card that does not pass this
# object gets eight more pixels under its last line than its neighbours in the
# same row. Every CardContent in this app passes CARD_PAD for that reason -- a
# bare one is a bug, not a variant.
CARD_PAD <- list(p = list(xs = 1.75, md = 2.5), `&:last-child` = list(pb = list(xs = 1.75, md = 2.5)))

# ---- vertical rhythm --------------------------------------------------------
# Three gaps, and only three. These were literals at some forty call sites, with
# eight distinct values between them, so gaps that mean the same thing did not
# match -- the declarations grid on the votes page closed with 24px and the same
# construct on the party page with 32px. Naming them makes the page's rhythm one
# thing to read rather than forty, and it is what keeps a new section consistent
# with the ones already there.
#
# The step between them is deliberately small. The unit of separation on this
# site is the card border, which already states where one block ends; the gap
# only has to keep the borders from reading as a single rule.
GAP_LABEL   <- 1      #  8px  a heading, or a subtitle, and the thing it labels
GAP_BLOCK   <- 2      # 16px  sibling blocks within a section
GAP_SECTION <- 3      # 24px  between sections

# **Containers own the spacing; a component carries no outer margin.**
#
# That rule is what page() and section() are for. The gap between two blocks
# used to be written on each block -- `Box(sx = list(mb = GAP_BLOCK), …)` around
# twenty-one of them, plus six at GAP_SECTION -- which put the same decision in
# twenty-seven places and made a page's rhythm something you had to reconstruct
# by reading every wrapper. Here it is stated once, by the container.
#
# It also removes a class of mistake the old form allowed: a bottom margin on a
# block that turns out to be the last visible one leaves a gap under the page,
# and a `loader_toggle()` block that is hidden takes its margin with it only
# because `display: none` happens to remove the margin too. A flex gap is not
# applied around a hidden child at all, so the arithmetic is the browser's.

# One page: its blocks in a column, evenly spaced. `sx` is for the rare nested
# use -- the mandate half of the party page, which is the same column of blocks
# behind its own rule.
page <- function(..., sx = NULL) {
  base <- list(display = "flex", flexDirection = "column", gap = GAP_BLOCK)
  Box(sx = if (is.null(sx)) base else utils::modifyList(base, sx), ...)
}

# A titled part of a page -- a heading and the thing it labels, held closer to
# each other than to what surrounds them. `mt` tops the container's gap up to
# GAP_SECTION, so a new section stands off further than a sibling block does.
section <- function(title, ...) {
  Box(
    sx = list(display = "flex", flexDirection = "column", gap = GAP_LABEL,
              mt = GAP_SECTION - GAP_BLOCK),
    if (!is.null(title)) Typography(title, variant = "h6"),
    ...
  )
}

# Two cards abreast on a wide screen, stacked below it. `split` is the first
# card's share of the twelve columns: even by default, uneven where one chart
# carries twenty ranked bars and the other two bands.
#
# Only for cards that are both always present. Where one of the pair can be
# hidden the page stacks them instead, because a half-width sibling with nothing
# beside it reads as a missing card.
card_pair <- function(a, b, split = 6) {
  Grid(
    container = TRUE, spacing = 2,
    Grid(size = list(xs = 12, lg = split), a),
    Grid(size = list(xs = 12, lg = 12 - split), b)
  )
}

# Headline figure sizes. A CHF total is the longest string on the page and the
# h4 default (2.125rem) wraps it onto three lines in a half-width phone cell.
KPI_VALUE_SX <- list(my = 0.5, lineHeight = 1.15,
                     fontSize = list(xs = "1.35rem", sm = "1.6rem", md = "2.125rem"))

# Mark a piece of KPI text as coming from the loader rather than from i18n:
#
#   loader_kpi("Ja-Lager", "yesFmt")                  static label
#   loader_kpi(from_loader("extraLabel"), "extra")    the loader names it too
#
# Two of these cards used to be written out by hand, forty lines between them,
# because the helper took only static text -- one page needs a loader-driven
# label, another a loader-driven sub.
from_loader <- function(selector) structure(selector, class = "spf_loaded")

# Render text that is either an ordinary string or a from_loader() selector.
# `make` builds the Typography, with the text where there is text and without it
# where the loader supplies it.
kpi_text <- function(x, make) {
  if (is.null(x)) NULL
  else if (inherits(x, "spf_loaded")) {
    useLoaderData(make(), as = "children", selector = unclass(x))
  } else {
    make(x)
  }
}

# The theme's overline tracking is 0.08em, which is right for a section label
# with a line to itself. A KPI card is half a phone screen wide, and at that
# measure the extra tracking pushed these labels to three lines above the
# figure, so they get less of it.
KPI_LABEL_SX <- list(display = "block", lineHeight = 1.3,
                     letterSpacing = list(xs = "0.03em", sm = "0.08em"))

# A KPI card whose value is filled in by the active route's loader. `accent`
# repeats the camp colour on the two camp figures, so blue-is-Yes / red-is-No is
# stated next to the numbers and not only inside the chart.
loader_kpi <- function(label, selector, sub = NULL, accent = NULL) {
  Card(
    sx = if (is.null(accent)) CARD_SX else utils::modifyList(CARD_SX, list(
      borderLeft = "4px solid", borderLeftColor = accent
    )),
    CardContent(
      sx = CARD_PAD,
      kpi_text(label, function(...) Typography(..., variant = "overline",
                                               color = "text.secondary",
                                               sx = KPI_LABEL_SX)),
      useLoaderData(Typography(variant = "h4", sx = KPI_VALUE_SX), selector = selector),
      kpi_text(sub, function(...) Typography(..., variant = "body2",
                                             color = "text.secondary"))
    )
  )
}

# What the chart is scoped to: the ballot, the scrutiny, the year. The picker
# that chose it is up in the page header and scrolls away, so a chart three
# screens down would otherwise state a total with no visible referent -- "who
# gives to the parties" is a different chart in 2023 and in 2024.
#
# Ordinary HTML above the chart. It used to be drawn inside the chart's SVG,
# which meant word-wrapping the text by hand into tspans and sizing the chart's
# top margin from the resulting line count -- about eighty lines of measured
# constants. Text in the card wraps by itself, and the card grows instead of the
# plot shrinking.
chart_caption <- function() {
  useLoaderData(
    Typography(variant = "caption", color = "text.secondary",
               sx = list(display = "block", fontWeight = 600, mb = 1,
                         lineHeight = 1.35)),
    as = "children", selector = "scope"
  )
}

chart_card <- function(lang, title, subtitle, chart) {
  Card(
    sx = CARD_SX,
    CardContent(
      sx = CARD_PAD,
      Typography(title, variant = "h6", sx = list(fontSize = list(xs = "1rem", md = "1.25rem"))),
      Typography(subtitle, variant = "body2", color = "text.secondary",
                 sx = list(mb = 1)),
      chart_caption(),
      chart,
      # Touch only. A mouse reader discovers the tooltip by moving over a bar;
      # a finger has no hover, and the tooltip lasts only as long as the press,
      # so on a phone the interaction has to be stated. `@media (hover: hover)`
      # rather than a width breakpoint: what matters is the input device, not
      # the size of the screen.
      Typography(
        t_("donations.hold_hint", lang), variant = "caption",
        color = "text.secondary",
        sx = list(display = "block", mt = 1,
                  `@media (hover: hover) and (pointer: fine)` = list(display = "none"))
      )
    )
  )
}

# The landing page's four entry cards.
#
# An entry card has to look like something you press. A bare bordered card with a
# hover effect does not, because the hover is only discoverable once you have
# already guessed -- and on a phone there is no hover at all. So the affordance
# is stated at rest: the title is in the link colour and carries the same arrow
# the in-table links use, and the card lifts onto a shadow on hover and back down
# on press.
entry_card <- function(to, title, text) {
  Grid(
    size = list(xs = 12, sm = 6, lg = 3),
    NavLink(
      to = to,
      className = "spf-themecard",
      Card(
        sx = utils::modifyList(CARD_SX, list(
          display = "flex", flexDirection = "column",
          transition = "border-color .15s ease, transform .15s ease, box-shadow .15s ease",
          `&:hover` = list(borderColor = SERIES[1], transform = "translateY(-3px)",
                           boxShadow = "0 10px 24px rgba(11,11,11,0.10)"),
          `&:active` = list(transform = "translateY(0)",
                            boxShadow = "0 2px 6px rgba(11,11,11,0.10)")
        )),
        CardContent(
          sx = utils::modifyList(CARD_PAD, list(flexGrow = 1)),
          # The arrow is pinned to the right edge rather than trailing the words,
          # so it sits in the same place on every card whether the title runs to
          # one line or two.
          Stack(
            direction = "row", spacing = 1, alignItems = "flex-start",
            sx = list(mb = 0.75),
            Typography(title, variant = "h6",
                       sx = list(color = SERIES[1], fontWeight = 700, flexGrow = 1)),
            Box(component = "span",
                sx = list(color = SERIES[1], fontWeight = 700, fontSize = "1.05rem",
                          lineHeight = 1.6, flex = "none",
                          transition = "transform .15s ease",
                          ".spf-themecard:hover &" = list(transform = "translateX(3px)")),
                HTML("&#8594;"))
          ),
          Typography(text, variant = "body2", color = "text.secondary")
        )
      )
    )
  )
}

grid_card <- function(...) {
  Card(sx = utils::modifyList(CARD_SX, list(p = list(xs = 0.5, md = 1))), ...)
}

# A neutral informational callout. Deliberately not an Alert: MUI's Alert
# severities carry the reserved status colours (good / warning / serious /
# critical), and none of these notes is a status. The accent is fixed rather
# than per-call -- see ACCENT_NOTE.
#
# Title and body are two columns on a wide screen, not two stacked blocks. A note
# is two or three sentences, and stacked in a full-width card they wrapped at a
# readable measure and left the right half of the card empty -- which reads as a
# rendering fault rather than as a deliberate short line. Side by side, the label
# column takes the space the empty gutter used to, the card is visibly full, and
# the body still wraps well short of the container. Below `md` the columns stack,
# which is what a phone did all along.
NOTE_LABEL_W <- 200          # the label column; the body flexes into the rest
NOTE_BODY_GAP <- 3           # theme spacing units between the two columns

note_card <- function(title, body, actions = NULL, accent = ACCENT_NOTE) {
  Card(
    sx = utils::modifyList(CARD_SX, list(
      borderLeft = "4px solid", borderLeftColor = accent
    )),
    CardContent(
      sx = CARD_PAD,
      Box(
        sx = list(display = "flex", flexDirection = list(xs = "column", md = "row"),
                  gap = list(xs = 0.5, md = NOTE_BODY_GAP)),
        Box(
          sx = list(flex = "0 0 auto", width = list(xs = "auto", md = NOTE_LABEL_W)),
          Typography(title, variant = "subtitle1")
        ),
        Box(
          sx = list(flex = "1 1 auto", minWidth = 0),
          Typography(body, variant = "body2", color = "text.secondary")
        )
      ),
      if (!is.null(actions)) {
        # Aligned with the body column, not with the label: the buttons act on
        # what the text just said. 8px per spacing unit, so the offset is the
        # label column plus the gap.
        Stack(direction = "row", spacing = 1,
              sx = list(mt = 1.5, flexWrap = "wrap", gap = 1,
                        ml = list(xs = 0,
                                  md = paste0(NOTE_LABEL_W + NOTE_BODY_GAP * 8, "px"))),
              actions)
      }
    )
  )
}

# Show or hide a block according to the loader. The component tree is declarative
# and built once in R, so there is no conditional render available; the loader
# returns a style object instead and the block is always mounted. That is cheap
# because every use is a note card or an empty state, and it keeps the "which
# blocks does this page have" question answerable by reading the page function.
loader_toggle <- function(selector, ...) {
  useLoaderData(Box(...), as = "style", selector = selector)
}

# The header every subject page opens with: the title and lead in one column,
# the page's own picker -- the ballot / election / year -- in the other.
#
# Two columns rather than a centred stack. A headline and a paragraph keep a
# readable line length however wide the window is, so on their own they fill
# rather less than the content column; the picker is what the header's other half
# is for. Stacking them and letting the text run the full width instead was worse
# both ways round -- either a 150-character measure or a narrow ribbon down the
# middle of an empty band.
#
# Under `md` the picker drops below the lead, which is the reading order on a
# phone anyway.
#
# The lead is capped in `ch`, not pixels: the cap is a line length (how far the
# eye travels back to the next line), and stating it in characters keeps it right
# whatever the container width is.
LEAD_MEASURE <- "64ch"

page_head <- function(title, lead, control = NULL) {
  Box(
    # The one margin a component still carries. page() spaces blocks at
    # GAP_BLOCK; the header stands off from the page like a section does, so it
    # tops that up to GAP_SECTION -- the same `mt = GAP_SECTION - GAP_BLOCK`
    # section() uses, written on the bottom because the header leads.
    sx = list(mb = GAP_SECTION - GAP_BLOCK),
    Box(
      # Aligned at the top, not the bottom. `flex-end` bottom-aligns the two
      # columns, which was fine while the control was a bare field but not once
      # it became a control_panel() -- a caption, a field and a two-line
      # subtitle. Bottom-aligning a box that tall against a title and one
      # paragraph pushed its top edge above the title, so the page appeared to
      # start with the picker and the heading looked dropped into the middle of
      # the row. Aligning the tops puts the title first whatever either column
      # grows to, which is also the order the page is read in.
      sx = list(display = "flex", flexDirection = list(xs = "column", md = "row"),
                alignItems = list(xs = "stretch", md = "flex-start"),
                justifyContent = "space-between", gap = list(xs = 2, md = 4)),
      Box(
        sx = list(flex = "1 1 auto", minWidth = 0),
        Typography(title, variant = "h4",
                   sx = list(mb = GAP_LABEL,
                             fontSize = list(xs = "1.6rem", sm = "1.9rem",
                                             md = "2.125rem"))),
        Typography(lead, variant = "body1", color = "text.secondary",
                   sx = list(maxWidth = LEAD_MEASURE))
      ),
      if (!is.null(control)) Box(sx = list(flex = "0 1 auto", minWidth = 0), control)
    )
  )
}

# ---- charts -----------------------------------------------------------------
# Axis and grid chrome shared by every chart: recessive hairlines, muted tick
# ink, and the axis line itself suppressed where the gridlines already carry it.
CHART_SX <- list(
  `.MuiChartsAxis-tickLabel` = list(fill = INK$muted, fontSize = 11),
  `.MuiChartsAxis-line`      = list(stroke = INK$baseline),
  `.MuiChartsAxis-tick`      = list(stroke = INK$baseline),
  `.MuiChartsGrid-line`      = list(stroke = INK$grid, strokeDasharray = "0"),
  `.MuiChartsLegend-series text` = list(fill = paste0(INK$secondary, " !important"), fontSize = "12px !important"),
  # A gap in the surface colour between adjacent fills. Drawn as a stroke rather
  # than as spacing because MUI X stacks segments flush: without it a
  # twenty-committee stack reads as one block with faint banding.
  #
  # The class is `MuiBarChart-element` in this version of MUI X, not
  # `MuiBarElement-root` -- the old selector matched nothing, so the separator
  # this comment describes was never actually drawn.
  #
  # Translucent rather than the flat surface colour, and 1.5px rather than 2px,
  # because the stroke straddles the edge and eats half its width into the fill.
  # A party year puts 15 segments under 2px thick on screen, and an opaque white
  # stroke painted those out completely -- which on this site means "nothing was
  # filed", the one thing a bar must never say by accident. At 85% the thin ones
  # survive as a pale tint of their own colour while the large ones still read as
  # cleanly separated.
  `.MuiBarChart-element` = list(stroke = "rgba(255,255,255,0.85)", strokeWidth = 1.5)
)

# Bars are thin marks: the default fills almost the whole band, which turns a
# two-band chart into two slabs. `categoryGapRatio` is the share of each band
# left empty -- and in this MUI X version it belongs to the *band axis*, not to
# the chart, where it is accepted and silently ignored. Loader-driven charts get
# it from `band()` in js/spf-charts.js; this is for the one chart still built in R.
BAR_GAP <- list(categoryGapRatio = 0.55, barGapRatio = 0.15)

# Value axes get few, widely spaced ticks -- franc labels are long ("CHF 2.0M")
# and the default tick count collides them into a grey smear.
TICKS <- 6L

# Which tooltip a chart gets is decided by how many rows it can produce.
#
# 'axis' heads the tooltip with the category -- the donor, the party, the camp --
# and lists the series at that position. That header is the only place a phone
# reader can see a category whose axis label had to be clipped to fit, so it is
# the default wherever the series count is bounded: one for a ranked chart, two
# for the camp-coloured ones, seven for a party's income components.
#
# 'item' is the exception, for the one chart that is not bounded: a busy ballot
# stacks seventeen committees on a band, and listing them measured 552px tall on
# an 844px phone, covering the chart it was describing. There the segment under
# the finger is named on its own, and the full breakdown is the table directly
# beneath -- which is also what discharges that chart's hidden legend.
TOOLTIP      <- list(trigger = "axis")
TOOLTIP_ITEM <- list(trigger = "item")

# A chart's height has to change with the viewport -- 520px of horizontal bars is
# most of a phone screen -- but `height` is a plain numeric prop on BarChart, not
# an sx value, so it cannot carry breakpoints. Omitting it instead makes MUI X
# size the chart from its parent, and the parent is a Box whose height *is* an sx
# breakpoint object. So every chart helper takes `height` as either a number or
# a list(xs =, md =) and wraps rather than passes it.
#
# Hidden from the accessibility tree, deliberately. A MUI X chart is an SVG with
# no accessible name, so what reaches a screen reader is the tick labels: a run
# of bare franc amounts and clipped committee names, in plot order, with nothing
# saying what they are. Given a name instead it would be a second description of
# the chart, written here and free to drift from what the bars actually show.
#
# Nothing is lost by hiding it, because every chart in this app sits above a
# DataGrid carrying the same figures -- the same "table view" relief the palette
# note at the top of this file leans on. The card's title and subtitle are
# ordinary text and are still read; so is the scope caption above the plot.
chart_box <- function(height, chart) {
  Box(sx = list(width = "100%", height = height),
      `aria-hidden` = "true", role = "presentation", chart)
}

# A chart's phone height is not one fraction of its desktop height: a ranked bar
# chart needs room per bar and shrinks least, a two-band comparison shrinks most.
# So each call site names both ends rather than deriving one from the other.
chart_h <- function(xs, md) list(xs = xs, md = md)

# Fold a chain of useLoaderData() wrappers over one chart, one per prop the
# loader supplies. The loader returns complete MUI X chart prop objects (margin,
# series, xAxis, yAxis) under `path`, including live valueFormatter functions --
# loader data is never serialised, so functions survive.
CHART_PROPS <- c("margin", "series", "xAxis", "yAxis")

loader_chart <- function(chart, path) {
  for (p in CHART_PROPS) {
    chart <- useLoaderData(chart, as = p, selector = paste0(path, ".", p))
  }
  chart
}

# Every chart in the app, in one function.
#
# There were three of these -- ranked horizontal bars, horizontal bars whose
# series bring their own colour, and vertical stacks -- and they differed only in
# the four arguments below. The data is what actually differs between charts, and
# that comes from the loader.
#
#   horizontal  bars run left to right, category labels top-to-bottom, largest
#               first (a ranking); otherwise bands run along the bottom (a
#               comparison). Gridlines follow: across the bars, never along them.
#   legend      off wherever the series count is unbounded -- a busy ballot
#               stacks 17 committees, and the table under the chart is the
#               identity channel there. On where the series are a fixed, small
#               set worth naming.
#   tooltip     see TOOLTIP / TOOLTIP_ITEM above.
#   colors      only ranked charts take the categorical palette; everywhere else
#               each series carries its own colour, because colour means the camp
#               or the income component rather than a slot order.
loader_bar <- function(path, height = 360, horizontal = TRUE, legend = FALSE,
                       tooltip = TOOLTIP) {
  chart_box(height, loader_chart(
    BarChart(
      layout = if (horizontal) "horizontal" else "vertical",
      skipAnimation = TRUE,
      hideLegend = !legend,
      borderRadius = 4,
      grid = if (horizontal) list(vertical = TRUE) else list(horizontal = TRUE),
      slotProps = list(tooltip = tooltip),
      sx = CHART_SX
    ),
    path
  ))
}

# ---- data grids -------------------------------------------------------------
# CSV export tuned for Swiss/German Excel: ';' as the column separator (Excel in
# a de/fr/it locale splits on ';', not ',') and a UTF-8 BOM so umlauts and
# accents survive the round trip.
csv_slot_props <- function(file_name) {
  list(toolbar = list(csvOptions = list(
    delimiter = ";", utf8WithBom = TRUE, fileName = file_name
  )))
}

# The grid's own chrome -- "Rows per page", the filter and column panels, the
# export menu, the "no rows" message -- ships in English and is the one part of
# the page i18n.R cannot reach, because it lives inside the DataGrid. MUI X
# publishes a translation per locale; this hands the grid the right one.
#
# There is no de-CH bundle and the difference is orthographic (ß), which does not
# occur in these strings, so German Switzerland reads deDE correctly.
GRID_LOCALE <- c(de = "deDE", fr = "frFR", it = "itIT")

#
# The bundle also brings its locale's number formatting into the pagination
# footer -- "1–25 von 1.174" in German, "1 174" in French -- and this app writes
# every figure the Swiss way, with an apostrophe, in all three languages on
# purpose (see CH_LOCALE). So the one string that carries digits is replaced;
# everything else in the bundle is text and is kept.
grid_locale_text <- function(lang) {
  JS(sprintf(
    "(function () {
       var base = window.jsmodule['@mui/x-data-grid/locales'].%s
                    .components.MuiDataGrid.defaultProps.localeText;
       var n = window.spf.fmt('%s').num;
       // `paginationDisplayedRows`, not `MuiTablePagination.labelDisplayedRows`:
       // this version of MUI X renders the footer itself and reads the top-level
       // key. Overriding only the nested one is accepted and silently ignored.
       return Object.assign({}, base, {
         paginationDisplayedRows: function (p) {
           var total = (p.count == null || p.count === -1) ? p.estimated : p.count;
           return n(p.from) + '–' + n(p.to) + ' %s ' +
                  (total == null ? n(p.to) : n(total));
         }
       });
     })()",
    GRID_LOCALE[[lang]], lang, tr("cols.rows_of", lang)
  ))
}

GRID_SX <- list(
  border = 0,
  `.MuiDataGrid-columnHeaderTitle` = list(fontWeight = 600),
  `.MuiDataGrid-cell` = list(borderColor = INK$grid),
  `.MuiDataGrid-columnHeaders` = list(borderColor = INK$grid)
)

# Columns are supplied by the loader so their headers are localised; rows too.
# `rows_selector` / `columns_selector` exist because several pages now show two
# grids -- the per-committee disclosures and the individual donations -- and one
# loader has to feed both.
loader_grid <- function(lang, file_name, height = 560, sort_field = "amount",
                        page_size = 25L, rows_selector = "rows",
                        columns_selector = "columns") {
  g <- DataGrid(
    getRowId = JS("(row) => row.id"),
    showToolbar = TRUE,
    disableRowSelectionOnClick = TRUE,
    localeText = grid_locale_text(lang),
    slotProps = csv_slot_props(file_name),
    density = "compact",
    initialState = list(
      pagination = list(paginationModel = list(pageSize = page_size)),
      sorting = list(sortModel = list(list(field = sort_field, sort = "desc")))
    ),
    pageSizeOptions = c(25L, 50L, 100L),
    # A phone gets a shorter grid: at 620px the pagination footer is off-screen,
    # so the reader cannot tell there is a second page. Which *columns* it gets
    # is decided in the loader, where the viewport width is readable (js/spf-charts.js).
    sx = utils::modifyList(GRID_SX, list(height = list(xs = 420, md = height)))
  )
  useLoaderData(
    useLoaderData(g, as = "rows", selector = rows_selector),
    as = "columns", selector = columns_selector
  )
}

# A one-line note directly above a grid whose cells link somewhere. The link
# styling alone (see LINK in js/spf-tables.js) says a cell is clickable once you notice
# it; this says so before you have to notice. Marked with the same arrow the
# entry cards use, so "→ means this goes somewhere" is one idea across the app.
click_hint <- function(lang) {
  Stack(
    direction = "row", spacing = 0.75, alignItems = "flex-start",
    sx = list(color = "text.secondary"),
    Box(component = "span", sx = list(color = SERIES[1], fontWeight = 700,
                                      lineHeight = 1.6),
        HTML("&#8594;")),
    Typography(t_("donations.click_hint", lang), variant = "body2",
               sx = list(maxWidth = "70ch"))
  )
}

# ---- filters ----------------------------------------------------------------
# The pickers and filters are the app: every page is "one ballot / one year /
# these donors", and choosing is the only thing a reader does. Left as plain
# small outlined fields they read as decoration on the off-white plane, so they
# get a white surface, a heavier outline, and a blue one on hover and focus.
CONTROL_SX <- list(
  backgroundColor = INK$surface,
  borderRadius = 2,
  `& .MuiOutlinedInput-notchedOutline` = list(
    borderColor = INK$baseline, borderWidth = "1.5px"),
  `&:hover .MuiOutlinedInput-notchedOutline` = list(borderColor = SERIES[1]),
  `& .MuiOutlinedInput-root.Mui-focused .MuiOutlinedInput-notchedOutline` = list(
    borderColor = SERIES[1], borderWidth = "2px"),
  `& .MuiInputLabel-root` = list(fontWeight = 600)
)

# The panel a set of controls sits in: a white card on the page plane, captioned
# with what the controls do. It is what makes a row of inputs read as "this is
# the control for this page" rather than as stray fields between two charts.
control_panel <- function(label, ..., sx = list()) {
  Box(
    sx = utils::modifyList(list(
      p = list(xs = 1.5, md = 2),
      border = "1px solid", borderColor = "divider", borderRadius = 3,
      backgroundColor = INK$plane
    ), sx),
    Typography(label, variant = "overline", color = "text.secondary",
               sx = list(display = "block", mb = 1, lineHeight = 1.2)),
    ...
  )
}

# Each control writes its value into the hash query string; that re-runs the
# route loader, which re-filters and re-aggregates. The URL is the only state.
filter_input <- function(key, label, options_selector, value_selector) {
  ac <- Autocomplete(
    multiple = TRUE,
    size = "small",
    limitTags = 1,
    disableCloseOnSelect = TRUE,
    onChange = JS(sprintf("(e, v) => window.spf.setParam('%s', v.map(o => o.key))", key)),
    isOptionEqualToValue = JS("(o, v) => o.key === v.key"),
    getOptionLabel = JS("(o) => o.label"),
    renderInput = JS(sprintf(
      "(params) => React.createElement(window.jsmodule['@mui/material'].TextField, { ...params, label: %s })",
      jsonlite::toJSON(label, auto_unbox = TRUE)
    )),
    # Full width on a phone: five 210px controls side by side wrap into a ragged
    # block, and a half-empty last row reads as a broken layout.
    sx = utils::modifyList(CONTROL_SX, list(
      width = list(xs = "100%", sm = "auto"), minWidth = list(xs = 0, sm = 210),
      flex = list(xs = "0 0 100%", sm = 1)))
  )
  useLoaderData(
    useLoaderData(ac, as = "options", selector = options_selector),
    as = "value", selector = value_selector
  )
}

# The picker the three subject pages are built around: one ballot, one election,
# one party year, one donor year. Single-select, because summing two ballots or
# two party years produces a figure with no referent -- the thing the old
# grand-total charts got wrong.
#
# The selection is a *path* segment rather than a query parameter, so a chosen
# ballot is a plain URL (#/fr/votes/28), the back button steps through
# selections, and the language switch keeps the choice.
# `show_label = FALSE` where the control sits in a control_panel() that already
# carries the caption: a floating label repeating the panel's own heading reads
# as a mistake. The label is still passed, because it becomes the control's
# accessible name -- a combobox that a screen reader announces as nothing is not
# an acceptable trade for a tidier box.
single_select <- function(label, base, options_selector = "options",
                          value_selector = "current", width = 460,
                          size = "medium", show_label = TRUE) {
  ac <- Autocomplete(
    multiple = FALSE,
    # Medium, not small: this control *is* the page, so it should not be the
    # smallest thing on it.
    size = size,
    disableClearable = TRUE,
    autoHighlight = TRUE,
    onChange = JS(sprintf(
      "(e, v) => { if (v) window.spf.goto('%s/' + encodeURIComponent(v.key)); }", base)),
    isOptionEqualToValue = JS("(o, v) => o.key === v.key"),
    getOptionLabel = JS("(o) => o.label"),
    renderInput = JS(sprintf(
      "(params) => React.createElement(window.jsmodule['@mui/material'].TextField, { ...params, %s })",
      if (show_label) sprintf("label: %s", jsonlite::toJSON(label, auto_unbox = TRUE))
      else sprintf("inputProps: { ...params.inputProps, 'aria-label': %s }",
                   jsonlite::toJSON(label, auto_unbox = TRUE))
    )),
    sx = utils::modifyList(CONTROL_SX, list(
      width = list(xs = "100%", sm = "auto"),
      minWidth = list(xs = 0, sm = 260), maxWidth = width, flex = 1))
  )
  useLoaderData(
    useLoaderData(ac, as = "options", selector = options_selector),
    as = "value", selector = value_selector
  )
}

min_amount_input <- function(label, any_label) {
  sel <- TextField(
    select = TRUE,
    size = "small",
    label = label,
    onChange = JS("(e) => window.spf.setParam('min', e.target.value)"),
    sx = utils::modifyList(CONTROL_SX, list(
      width = list(xs = "100%", sm = "auto"), minWidth = list(xs = 0, sm = 170))),
    MenuItem(value = "", any_label),
    MenuItem(value = "10000", "≥ CHF 10'000"),
    MenuItem(value = "50000", "≥ CHF 50'000"),
    MenuItem(value = "100000", "≥ CHF 100'000"),
    MenuItem(value = "500000", "≥ CHF 500'000"),
    MenuItem(value = "1000000", "≥ CHF 1'000'000")
  )
  useLoaderData(sel, as = "value", selector = "curMin")
}

# ---- navigation -------------------------------------------------------------
# The mark, in one place. It is drawn twice -- in the app bar and, through
# favicon_uri() below, as the browser tab icon -- and the two must not drift.
# Inline SVG rather than the flag emoji, which Windows renders as the letters
# "CH", and rather than an icon package, so the built page still makes no
# network request.
swiss_cross <- function(size = 26, style = "") {
  sprintf(paste0(
    "<svg width='%d' height='%d' viewBox='0 0 32 32' xmlns='http://www.w3.org/2000/svg' ",
    "style='%s'>",
    "<rect width='32' height='32' rx='6' fill='%s'/>",
    "<rect x='13' y='6' width='6' height='20' fill='#fff'/>",
    "<rect x='6' y='13' width='20' height='6' fill='#fff'/></svg>"
  ), size, size, style, INK$swiss_red)
}

# The same mark as a `data:` URI for <link rel="icon">. Percent-encoded rather
# than base64: the payload is a hundred bytes of ASCII, and only `#` and the
# angle brackets actually have to be escaped for it to survive inside an
# attribute.
favicon_uri <- function() {
  svg <- swiss_cross(32)
  svg <- gsub("#", "%23", svg, fixed = TRUE)
  svg <- gsub("<", "%3C", svg, fixed = TRUE)
  svg <- gsub(">", "%3E", svg, fixed = TRUE)
  svg <- gsub('"', "%22", svg, fixed = TRUE)
  paste0("data:image/svg+xml,", svg)
}

nav_link <- function(to, label, end = FALSE) {
  NavLink(to = to, end = end, className = "spf-navlink", label)
}

# The six section links, in one place: the app bar renders them inline on a wide
# screen and the side sheet renders the same list on a phone, so they can never
# drift apart.
NAV_SECTIONS <- c("votes", "elections", "parties", "donors", "data")

nav_links <- function(lang) {
  c(
    list(nav_link(p_(lang), t_("nav.home", lang), end = TRUE)),
    lapply(NAV_SECTIONS, function(s) nav_link(p_(lang, s), t_(paste0("nav.", s), lang)))
  )
}

# The id the nav panel binds to. Not a per-language id: all three language shells
# exist in the source, but React Router mounts only the routed one, so there is
# exactly one hamburger in the document at any moment.
NAV_TRIGGER_ID <- "spf-nav-trigger"

# The hamburger. An inline SVG rather than an icon font or @mui/icons-material,
# for the same reason the Swiss cross in the app bar is one: the built page makes
# no network request and carries no icon package.
#
# No onClick: the panel binds itself to this element by id (see nav_sheet).
menu_button <- function(lang) {
  IconButton(
    id = NAV_TRIGGER_ID,
    `aria-label` = t_("nav.menu", lang),
    sx = list(display = list(xs = "inline-flex", md = "none"), color = "#fff",
              mr = 0.5, ml = -1),
    HTML(paste0(
      "<svg width='22' height='22' viewBox='0 0 24 24' fill='none' ",
      "stroke='currentColor' stroke-width='2' stroke-linecap='round'>",
      "<path d='M3 6h18M3 12h18M3 18h18'/></svg>"
    ))
  )
}

# The mobile navigation panel.
#
# `Drawer.triggerId()` holds `open` in the wrapper's own React state and binds to
# the hamburger through a delegated document listener, so this needs neither a
# server nor state of ours -- `open` is owned by the wrapper and must not be
# passed. It replaces a hand-rolled <dialog>, which was there on the false
# premise that MUI's Drawer can only be driven by a controlled `open` prop.
#
# `closeOnLinkClick` is the default and closes the panel when a click lands on a
# descendant <a>. The links are NavLinks, so they navigate without a page load
# and would otherwise leave the panel open over the page they just opened. Unlike
# the listener this replaces -- which sat on the whole nav container -- a click
# that *misses* a link no longer closes the panel.
#
# It is dismissed by the backdrop, by Esc and by tapping a link. There is no X:
# the wrapper exposes no imperative close, so a button of ours would have nothing
# to call. Both remaining affordances are MUI's Modal defaults.
nav_sheet <- function(lang) {
  Drawer.triggerId(
    triggerId = NAV_TRIGGER_ID,
    anchor = "right",
    width = "min(84vw, 320px)",
    slotProps = list(paper = list(sx = list(
      bgcolor = INK$bar, color = "#fff",
      # The paper carries an elevation overlay and a divider by default; both
      # read as grime on a panel that is already the darkest surface here.
      backgroundImage = "none", border = 0,
      px = "12px", pt = "14px",
      pb = "calc(14px + env(safe-area-inset-bottom))",
      boxShadow = "-18px 0 40px rgba(0,0,0,0.35)"
    ))),
    Box(
      component = "nav", className = "spf-sheet-nav",
      `aria-label` = t_("nav.label", lang),
      nav_links(lang)
    )
  )
}

# The "the CSVs are not published yet" note. A native <dialog> rather than
# `Dialog.triggerId` -- see window.spf.openDialog in js/spf-runtime.js for why the many
# triggers on the data page rule the wrapper out here.
# Rendered only while DATA_PUBLISHED is FALSE (see build_site.R).
soon_dialog <- function(lang) {
  tags$dialog(
    class = "spf-modal",
    `aria-label` = t_("data.soon_title", lang),
    Typography(t_("data.soon_title", lang), variant = "h6", sx = list(mb = 1)),
    Typography(t_("data.soon_text", lang), variant = "body2", color = "text.secondary"),
    Box(
      sx = list(display = "flex", justifyContent = "flex-end", mt = 2),
      Button(t_("data.soon_close", lang), variant = "contained", size = "small",
             onClick = JS("() => window.spf.closeSoon()"))
    )
  )
}

# The language switch rewrites only the first hash segment, so the route and all
# filters carry over. That works because every filter value in the URL is a
# language-neutral key (see prepare_data.R), never a translated label.
lang_switch <- function(current) {
  Box(
    className = "spf-langs",
    lapply(LANGS, function(l) {
      tags$button(
        type = "button",
        class = paste("spf-lang", if (l == current) "active" else ""),
        # `onClick` with a function, not an `onclick` attribute: the tree is
        # rendered by React, which silently drops unknown lower-case DOM
        # attributes -- the button looks right and does nothing.
        onClick = JS(sprintf("() => window.spf.setLang('%s')", l)),
        # The button shows a two-letter code; the full endonym is what assistive
        # technology and a hover tooltip need.
        lang = l,
        title = tr("lang_name", l),
        `aria-label` = tr("lang_name", l),
        `aria-current` = if (l == current) "true" else NULL,
        toupper(l)
      )
    })
  )
}

# The first focusable thing in the app. Without it, a keyboard or screen-reader
# reader re-traverses the six nav links and the three language buttons on every
# single navigation before reaching the page.
#
# A <button>, not the usual `<a href="#main">`: this app is hash-routed, so an
# anchor to a fragment would overwrite the route and navigate the reader away
# from the page they were trying to skip into.
skip_link <- function(lang) {
  tags$button(
    type = "button", class = "spf-skip",
    onClick = JS("() => window.spf.skipToMain()"),
    t_("skip_link", lang)
  )
}

# The stylesheet is css/app.css -- a real file, so an editor highlights it and a
# formatter can read it. The handful of values it shares with the R theme travel
# as CSS custom properties in a :root{} block prefixed here, which is what keeps
# the .css file static: nothing rewrites it on the way to the page.
CSS_VARS <- function() list(
  "font"      = FONT_STACK,
  "on-bar"    = INK$on_bar,
  "series1"   = SERIES[1]
)

app_css <- function(path = "css/app.css") {
  if (!file.exists(path)) stop("missing ", path, call. = FALSE)
  css <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  vars <- CSS_VARS()
  # A var() naming a value R does not supply resolves to nothing and the rule is
  # silently dropped, so it is a build failure instead -- the same guarantee the
  # old `{token}` substitution gave.
  used <- unique(regmatches(css, gregexpr("--spf-[a-z0-9-]+", css))[[1]])
  unknown <- setdiff(used, paste0("--spf-", names(vars)))
  if (length(unknown)) {
    stop("app_css(): ", path, " uses ", paste(unknown, collapse = ", "),
         ", which CSS_VARS() does not define", call. = FALSE)
  }

  root <- sprintf(":root{%s}", paste(
    sprintf("--spf-%s:%s;", names(vars), unlist(vars)), collapse = ""))
  tags$style(HTML(paste0(root, "\n", css)))
}
