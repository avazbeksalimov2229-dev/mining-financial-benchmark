# DAX: Mining Financial Benchmark

All measures live in an empty table called **`_Measures`**. The folder names are the **Display folder** values.
`fact_financials` is a long table: one row per company, fiscal year and metric, in US dollars.

---

## 1. Calculated tables

```dax
dim_year = SELECTCOLUMNS ( GENERATESERIES ( 2016, 2025, 1 ), "Year", [Value] )
```

```dax
-- Field parameter: lets the viewer pick the measure the ranking chart is sorted by
Rank By =
{
    ( "Revenue", NAMEOF ( [Revenue ($B)] ), 0 ),
    ( "Net income", NAMEOF ( [Net Income ($B)] ), 1 ),
    ( "Free cash flow", NAMEOF ( [Free Cash Flow ($B)] ), 2 ),
    ( "Net margin", NAMEOF ( [Net Margin] ), 3 ),
    ( "FCF margin", NAMEOF ( [FCF Margin] ), 4 )
}
```

## 2. Relationships (all one-to-many, single direction)

| From (one) | To (many) |
|---|---|
| `dim_company[ticker]` | `fact_financials[ticker]` |
| `dim_metric[metric]` | `fact_financials[metric]` |
| `dim_year[Year]` | `fact_financials[fiscal_year]`, `fact_metal_prices[year]` |

---

## 3. Base amounts (folder: `1 Amounts`)

```dax
Value = SUM ( fact_financials[value_usd] )

Amount ($M) = DIVIDE ( [Value], 1e6 )

Revenue = CALCULATE ( [Value], dim_metric[metric] = "Revenue" )

Profit Before Tax = CALCULATE ( [Value], dim_metric[metric] = "Profit before tax" )

Net Income = CALCULATE ( [Value], dim_metric[metric] = "Net income" )

Depreciation & Amortization = CALCULATE ( [Value], dim_metric[metric] = "Depreciation & amortization" )

Operating Cash Flow = CALCULATE ( [Value], dim_metric[metric] = "Operating cash flow" )

Capex = CALCULATE ( [Value], dim_metric[metric] = "Capex" )

Dividends Paid = CALCULATE ( [Value], dim_metric[metric] = "Dividends paid" )

Total Assets = CALCULATE ( [Value], dim_metric[metric] = "Total assets" )

Cash = CALCULATE ( [Value], dim_metric[metric] = "Cash" )

Total Debt = CALCULATE ( [Value], dim_metric[metric] = "Total debt" )

Shareholders Equity = CALCULATE ( [Value], dim_metric[metric] = "Shareholders' equity" )

-- royalty and streaming companies tag no PP&E capex: their free cash flow equals operating cash flow
Free Cash Flow =
VAR ocf = [Operating Cash Flow]
RETURN IF ( NOT ISBLANK ( ocf ), ocf - [Capex] )

-- companies without a debt tag (no borrowings) count as zero debt
Net Debt =
VAR c = [Cash]
VAR d = [Total Debt]
RETURN IF ( NOT ISBLANK ( c ) || NOT ISBLANK ( d ), d - c )

-- cash left after capex and dividends
Cash After Dividends = [Free Cash Flow] - [Dividends Paid]

Revenue ($B) = DIVIDE ( [Revenue], 1e9 )

Net Income ($B) = DIVIDE ( [Net Income], 1e9 )

Free Cash Flow ($B) = DIVIDE ( [Free Cash Flow], 1e9 )

Net Debt ($B) = DIVIDE ( [Net Debt], 1e9 )

Operating Cash Flow ($B) = DIVIDE ( [Operating Cash Flow], 1e9 )

Capex ($B) = DIVIDE ( [Capex], 1e9 )

Dividends Paid ($B) = DIVIDE ( [Dividends Paid], 1e9 )

Cash After Dividends ($B) = DIVIDE ( [Cash After Dividends], 1e9 )

Total Debt ($B) = DIVIDE ( [Total Debt], 1e9 )

Cash ($B) = DIVIDE ( [Cash], 1e9 )

Shareholders Equity ($B) = DIVIDE ( [Shareholders Equity], 1e9 )

Total Assets ($B) = DIVIDE ( [Total Assets], 1e9 )
```

## 4. Ratios (folder: `2 Ratios`)

Ratios divide the totals, so a segment margin is the margin of the segment's combined numbers, not an average of margins.

```dax
Net Margin = DIVIDE ( [Net Income], [Revenue] )

Pre-tax Margin = DIVIDE ( [Profit Before Tax], [Revenue] )

OCF Margin = DIVIDE ( [Operating Cash Flow], [Revenue] )

FCF Margin = DIVIDE ( [Free Cash Flow], [Revenue] )

Capex Intensity = DIVIDE ( [Capex], [Revenue] )

-- share of profit paid out; blank in loss years
Payout Ratio =
VAR ni = [Net Income]
RETURN IF ( ni > 0, DIVIDE ( [Dividends Paid], ni ) )

Return on Equity = DIVIDE ( [Net Income], [Shareholders Equity] )

-- years of operating cash flow needed to repay net debt (negative = net cash)
Net Debt to OCF = DIVIDE ( [Net Debt], [Operating Cash Flow] )

Debt to Equity = DIVIDE ( [Total Debt], [Shareholders Equity] )
```

## 5. Growth (folder: `3 Growth`)

Year-on-year growth is **like-for-like**: a company counts only when it reported both years,
so a late filer does not look like a fall in revenue.

```dax
Revenue YoY % =
VAR y = MAX ( dim_year[Year] )
VAR t =
    ADDCOLUMNS (
        VALUES ( dim_company[ticker] ),
        "@cur", [Revenue],
        "@prev", CALCULATE ( [Revenue], dim_year[Year] = y - 1 )
    )
VAR both = FILTER ( t, NOT ISBLANK ( [@cur] ) && NOT ISBLANK ( [@prev] ) )
RETURN DIVIDE ( SUMX ( both, [@cur] ) - SUMX ( both, [@prev] ), SUMX ( both, [@prev] ) )

Net Income YoY % =
VAR y = MAX ( dim_year[Year] )
VAR t =
    ADDCOLUMNS (
        VALUES ( dim_company[ticker] ),
        "@cur", [Net Income],
        "@prev", CALCULATE ( [Net Income], dim_year[Year] = y - 1 )
    )
VAR both = FILTER ( t, NOT ISBLANK ( [@cur] ) && NOT ISBLANK ( [@prev] ) )
VAR prev = SUMX ( both, [@prev] )
RETURN IF ( prev > 0, DIVIDE ( SUMX ( both, [@cur] ) - prev, prev ) )

-- revenue as an index, 2016 = 100, for companies that reported 2016
Revenue Index (2016 base) =
VAR t =
    ADDCOLUMNS (
        VALUES ( dim_company[ticker] ),
        "@cur", [Revenue],
        "@base", CALCULATE ( [Revenue], dim_year[Year] = 2016 )
    )
VAR both = FILTER ( t, NOT ISBLANK ( [@cur] ) && NOT ISBLANK ( [@base] ) )
RETURN DIVIDE ( SUMX ( both, [@cur] ), SUMX ( both, [@base] ) ) * 100

Companies Reporting = COUNTROWS ( FILTER ( VALUES ( dim_company[ticker] ), NOT ISBLANK ( [Revenue] ) ) )

Revenue Rank =
IF ( NOT ISBLANK ( [Revenue] ), RANKX ( ALLSELECTED ( dim_company[company] ), [Revenue] ) )
```

## 6. Metal prices (folder: `4 Prices`)

World Bank Pink Sheet monthly averages; a yearly value is the average of the 12 months.

```dax
Gold Price = CALCULATE ( AVERAGE ( fact_metal_prices[price_usd] ), fact_metal_prices[metal] = "Gold" )

Copper Price = CALCULATE ( AVERAGE ( fact_metal_prices[price_usd] ), fact_metal_prices[metal] = "Copper" )

Silver Price = CALCULATE ( AVERAGE ( fact_metal_prices[price_usd] ), fact_metal_prices[metal] = "Silver" )

Gold Price YoY % =
VAR y = MAX ( dim_year[Year] )
VAR prev = CALCULATE ( [Gold Price], dim_year[Year] = y - 1 )
RETURN DIVIDE ( [Gold Price] - prev, prev )

Copper Price YoY % =
VAR y = MAX ( dim_year[Year] )
VAR prev = CALCULATE ( [Copper Price], dim_year[Year] = y - 1 )
RETURN DIVIDE ( [Copper Price] - prev, prev )

Gold Price Index (2016 base) = DIVIDE ( [Gold Price], CALCULATE ( [Gold Price], dim_year[Year] = 2016 ) ) * 100

Copper Price Index (2016 base) = DIVIDE ( [Copper Price], CALCULATE ( [Copper Price], dim_year[Year] = 2016 ) ) * 100

-- price of the metal each company mostly sells (one company selected)
Main Metal Price =
SWITCH ( SELECTEDVALUE ( dim_company[primary_metal] ), "Gold", [Gold Price], "Copper", [Copper Price] )

-- the price change of the metal each company mostly sells
Main Metal Price YoY % =
SWITCH (
    SELECTEDVALUE ( dim_company[primary_metal] ),
    "Gold", [Gold Price YoY %],
    "Copper", [Copper Price YoY %]
)
```

## 7. Peers (folder: `5 Peers`)

```dax
-- median of the companies in the same segment, same year
Net Margin (Segment Median) =
VAR seg = SELECTEDVALUE ( dim_company[segment] )
RETURN MEDIANX ( FILTER ( ALL ( dim_company ), dim_company[segment] = seg ), [Net Margin] )

FCF Margin (Segment Median) =
VAR seg = SELECTEDVALUE ( dim_company[segment] )
RETURN MEDIANX ( FILTER ( ALL ( dim_company ), dim_company[segment] = seg ), [FCF Margin] )

Net Debt to OCF (Segment Median) =
VAR seg = SELECTEDVALUE ( dim_company[segment] )
RETURN MEDIANX ( FILTER ( ALL ( dim_company ), dim_company[segment] = seg ), [Net Debt to OCF] )

Return on Equity (Segment Median) =
VAR seg = SELECTEDVALUE ( dim_company[segment] )
RETURN MEDIANX ( FILTER ( ALL ( dim_company ), dim_company[segment] = seg ), [Return on Equity] )
```

## 8. Colors (folder: `6 Colors`)

```dax
Margin Color =
VAR m = [Net Margin]
RETURN
    SWITCH ( TRUE (), ISBLANK ( m ), BLANK (), m < 0, "#C0392B", m < 0.10, "#E8B04B", m < 0.25, "#8DB580", "#2E8B57" )

Net Debt Color = IF ( [Net Debt] > 0, "#B87333", "#2E8B57" )

Growth Color = IF ( [Revenue YoY %] < 0, "#C0392B", "#2E8B57" )

-- heat map for the company x year margin matrix
Margin Heat Color =
VAR m = [Net Margin]
RETURN
    SWITCH (
        TRUE (),
        ISBLANK ( m ), BLANK (),
        m < -0.10, "#E8A39B",
        m < 0, "#F4CDC8",
        m < 0.10, "#F7E8C6",
        m < 0.20, "#E3EFD9",
        m < 0.35, "#C2DFB4",
        "#9CCB8A"
    )
```

## 9. Labels (folder: `9 Labels`)

```dax
Selected Year = SELECTEDVALUE ( dim_year[Year], MAX ( dim_year[Year] ) )

KPI Revenue Sub =
FORMAT ( [Revenue YoY %], "+0%;-0%" ) & " like-for-like vs " & ( [Selected Year] - 1 )

KPI Net Income Sub = "Net margin " & FORMAT ( [Net Margin], "0.0%" )

KPI FCF Sub = "FCF margin " & FORMAT ( [FCF Margin], "0.0%" )

KPI Gold Sub = FORMAT ( [Gold Price YoY %], "+0%;-0%" ) & " vs " & ( [Selected Year] - 1 ) & " · $/troy oz"

KPI Copper Sub = FORMAT ( [Copper Price YoY %], "+0%;-0%" ) & " vs " & ( [Selected Year] - 1 ) & " · $/tonne"

KPI Net Debt Sub =
VAR r = [Net Debt to OCF]
RETURN IF ( [Net Debt] < 0, "Net cash", FORMAT ( r, "0.0" ) & " years of OCF" )

KPI Peer Margin Sub = "Segment median " & FORMAT ( [Net Margin (Segment Median)], "0.0%" )

KPI Peer FCF Sub = "Segment median " & FORMAT ( [FCF Margin (Segment Median)], "0.0%" )

KPI Peer ROE Sub = "Segment median " & FORMAT ( [Return on Equity (Segment Median)], "0.0%" )

Title Company =
VAR c = SELECTEDVALUE ( dim_company[company], "Select one company" )
RETURN
    IF (
        HASONEVALUE ( dim_company[ticker] ),
        c & "  ·  " & SELECTEDVALUE ( dim_company[segment] ) & "  ·  " & SELECTEDVALUE ( dim_company[hq_country] )
            & "  ·  " & SELECTEDVALUE ( dim_company[reporting_standard] ),
        c
    )

Latest Filing = "Latest SEC filing in the data: " & FORMAT ( CALCULATE ( MAX ( fact_financials[filed] ), REMOVEFILTERS () ), "d mmm yyyy" )
```
