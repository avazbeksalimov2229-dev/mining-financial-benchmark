// Power Query (M) - Mining Financial Benchmark
// ------------------------------------------------------------------------------
// Every table is read live from the web at refresh time: no local files and no folder to set.
// Parameters
//   SecUserAgent  SEC asks automated clients to identify themselves: "Your Name your@email.com"
//   WorldBankFile path of the Pink Sheet file on thedocs.worldbank.org (it changes once a year)
//
// Web.Contents uses a fixed base URL + RelativePath, so the report can also be refreshed on a schedule in
// the Power BI Service. Company and concept lists are written inside the queries (not read from files),
// so no query mixes a web source with a file source and Power BI does not ask for privacy levels.
// data\companies.csv and data\concept_map.csv hold the same lists for scripts\fetch_data.py, which writes
// an offline copy of the same tables to data\snapshot\ (used to cross-check the Power Query result).
// ------------------------------------------------------------------------------


// ---------- fnCompanyFacts ----------
// One SEC registrant: every XBRL fact it has ever filed (US GAAP and IFRS), as a record.
(cik as text) as record =>
let
    Response = Web.Contents("https://data.sec.gov", [
        RelativePath = "api/xbrl/companyfacts/CIK" & Text.PadStart(cik, 10, "0") & ".json",
        Headers = [#"User-Agent" = SecUserAgent]
    ]),
    Facts = Json.Document(Response)[facts]
in
    Facts


// ---------- fact_financials ----------
// Annual values of 11 metrics for 16 companies, 2016-2025, straight from the SEC company facts API.
let
    // AngloGold Ashanti has two SEC registrants: the old Ltd (to 2022) and the new plc (from 2023)
    Companies = #table(type table [ticker = text, cik = text], {
        {"NEM", "1164727"}, {"B", "756894"}, {"AEM", "2809"}, {"KGC", "701818"}, {"GFI", "1172724"},
        {"AU", "1067428"}, {"AU", "1973832"}, {"AGI", "1178819"}, {"IAG", "1203464"}, {"FCX", "831259"},
        {"SCCO", "1001838"}, {"HBM", "1322422"}, {"BHP", "811809"}, {"RIO", "863064"}, {"WPM", "1323404"},
        {"FNV", "1456346"}, {"RGLD", "85535"}}),
    // metric -> XBRL concepts that report it, best first (same list as data\concept_map.csv)
    ConceptMap = #table(type table [metric = text, taxonomy = text, concept = text, period_type = text, priority = Int64.Type], {
        {"Revenue", "us-gaap", "Revenues", "duration", 1},
        {"Revenue", "us-gaap", "RevenueFromContractWithCustomerExcludingAssessedTax", "duration", 2},
        {"Revenue", "us-gaap", "SalesRevenueNet", "duration", 3},
        {"Revenue", "ifrs-full", "Revenue", "duration", 4},
        {"Revenue", "ifrs-full", "RevenueFromContractsWithCustomers", "duration", 5},
        {"Profit before tax", "us-gaap", "IncomeLossFromContinuingOperationsBeforeIncomeTaxesExtraordinaryItemsNoncontrollingInterest", "duration", 1},
        {"Profit before tax", "us-gaap", "IncomeLossFromContinuingOperationsBeforeIncomeTaxesMinorityInterestAndIncomeLossFromEquityMethodInvestments", "duration", 2},
        {"Profit before tax", "ifrs-full", "ProfitLossBeforeTax", "duration", 3},
        {"Net income", "us-gaap", "NetIncomeLoss", "duration", 1},
        {"Net income", "us-gaap", "NetIncomeLossAvailableToCommonStockholdersBasic", "duration", 2},
        {"Net income", "ifrs-full", "ProfitLossAttributableToOwnersOfParent", "duration", 3},
        {"Net income", "ifrs-full", "ProfitLoss", "duration", 4},
        {"Depreciation & amortization", "us-gaap", "DepreciationDepletionAndAmortization", "duration", 1},
        {"Depreciation & amortization", "us-gaap", "DepreciationAndAmortization", "duration", 2},
        {"Depreciation & amortization", "ifrs-full", "DepreciationAndAmortisationExpense", "duration", 3},
        {"Depreciation & amortization", "ifrs-full", "AdjustmentsForDepreciationAndAmortisationExpense", "duration", 4},
        {"Depreciation & amortization", "ifrs-full", "DepreciationExpense", "duration", 5},
        {"Operating cash flow", "us-gaap", "NetCashProvidedByUsedInOperatingActivities", "duration", 1},
        {"Operating cash flow", "us-gaap", "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations", "duration", 2},
        {"Operating cash flow", "ifrs-full", "CashFlowsFromUsedInOperatingActivities", "duration", 3},
        {"Capex", "us-gaap", "PaymentsToAcquirePropertyPlantAndEquipment", "duration", 1},
        {"Capex", "us-gaap", "PaymentsToAcquireProductiveAssets", "duration", 2},
        {"Capex", "us-gaap", "PaymentsToAcquireMiningAssets", "duration", 3},
        {"Capex", "ifrs-full", "PurchaseOfPropertyPlantAndEquipmentClassifiedAsInvestingActivities", "duration", 4},
        {"Capex", "ifrs-full", "PurchaseOfPropertyPlantAndEquipmentIntangibleAssetsOtherThanGoodwillInvestmentPropertyAndOtherNoncurrentAssets", "duration", 5},
        {"Capex", "ifrs-full", "PurchaseOfMiningAssetsClassifiedAsInvestingActivities", "duration", 6},
        {"Dividends paid", "us-gaap", "PaymentsOfDividendsCommonStock", "duration", 1},
        {"Dividends paid", "us-gaap", "PaymentsOfDividends", "duration", 2},
        {"Dividends paid", "ifrs-full", "DividendsPaidToEquityHoldersOfParentClassifiedAsFinancingActivities", "duration", 3},
        {"Dividends paid", "ifrs-full", "DividendsPaidClassifiedAsFinancingActivities", "duration", 4},
        {"Total assets", "us-gaap", "Assets", "instant", 1},
        {"Total assets", "ifrs-full", "Assets", "instant", 2},
        {"Cash", "us-gaap", "CashAndCashEquivalentsAtCarryingValue", "instant", 1},
        {"Cash", "ifrs-full", "CashAndCashEquivalents", "instant", 2},
        {"Total debt", "us-gaap", "LongTermDebt", "instant", 1},
        {"Total debt", "us-gaap", "DebtLongtermAndShorttermCombinedAmount", "instant", 2},
        {"Total debt", "us-gaap", "LongTermDebtNoncurrent", "instant", 3},
        {"Total debt", "ifrs-full", "Borrowings", "instant", 4},
        {"Total debt", "ifrs-full", "LongtermBorrowings", "instant", 5},
        {"Total debt", "ifrs-full", "NoncurrentPortionOfNoncurrentBorrowings", "instant", 6},
        {"Shareholders' equity", "us-gaap", "StockholdersEquity", "instant", 1},
        {"Shareholders' equity", "ifrs-full", "EquityAttributableToOwnersOfParent", "instant", 2},
        {"Shareholders' equity", "ifrs-full", "Equity", "instant", 3}}),
    AnnualForms = {"10-K", "10-K/A", "10-KT", "10-KT/A", "20-F", "20-F/A", "40-F", "40-F/A"},

    // 1. one API call per registrant, then every (company, concept) pair
    WithFacts = Table.AddColumn(Companies, "facts", each fnCompanyFacts([cik])),
    WithMap = Table.AddColumn(WithFacts, "map", each ConceptMap),
    Pairs = Table.ExpandTableColumn(WithMap, "map", {"metric", "taxonomy", "concept", "period_type", "priority"}),
    // 2. the USD values of that concept (an empty list when the company never used it)
    Values = Table.AddColumn(Pairs, "values", each
        let c = Record.FieldOrDefault(Record.FieldOrDefault([facts], [taxonomy], []), [concept], null)
        in if c = null then {} else Record.FieldOrDefault(c[units], "USD", {})),
    Slim = Table.RemoveColumns(Values, {"facts"}),
    Listed = Table.SelectRows(Table.ExpandListColumn(Slim, "values"), each [values] <> null),
    Fields = Table.ExpandRecordColumn(Listed, "values", {"start", "end", "val", "form", "filed", "accn"}),
    // 3. annual reports only
    Annual = Table.SelectRows(Fields, each List.Contains(AnnualForms, [form])),
    Typed = Table.TransformColumnTypes(Annual, {{"start", type date}, {"end", type date}, {"filed", type date},
        {"val", type number}}, "en-US"),
    // 4. flows must cover a full year (350-380 days); balances have no start date
    Flows = Table.SelectRows(Typed, each [period_type] = "duration" and [start] <> null
        and Duration.Days([end] - [start]) >= 350 and Duration.Days([end] - [start]) <= 380),
    // 5. balances only at a fiscal year-end (the end date of an annual flow), so June year-ends work too
    YearEnds = Table.RenameColumns(Table.Distinct(Table.SelectColumns(Flows, {"ticker", "end"})),
        {{"ticker", "ye_ticker"}, {"end", "ye_end"}}),
    Instants = Table.SelectRows(Typed, each [period_type] = "instant" and [start] = null),
    Balances = Table.RemoveColumns(Table.Join(Instants, {"ticker", "end"}, YearEnds, {"ye_ticker", "ye_end"},
        JoinKind.Inner), {"ye_ticker", "ye_end"}),
    Kept = Table.Combine({Flows, Balances}),
    WithYear = Table.AddColumn(Kept, "fiscal_year", each Date.Year([end]), Int64.Type),
    InRange = Table.SelectRows(WithYear, each [fiscal_year] >= 2016 and [fiscal_year] <= 2025),
    // 6. one value per company, metric and year: best concept first, then the latest filing (restatements win)
    Sorted = Table.Buffer(Table.Sort(InRange, {{"priority", Order.Ascending}, {"filed", Order.Descending}})),
    Best = Table.Group(Sorted, {"ticker", "fiscal_year", "metric"}, {{"row", each Table.First(_), type record}}),
    Expanded = Table.ExpandRecordColumn(Best, "row", {"end", "val", "taxonomy", "concept", "form", "filed", "accn", "cik"}),
    Concept = Table.AddColumn(Expanded, "xbrl_concept", each [taxonomy] & ":" & [concept], type text),
    Renamed = Table.RenameColumns(
        Table.SelectColumns(Concept, {"ticker", "fiscal_year", "end", "metric", "val", "xbrl_concept", "form", "filed", "accn", "cik"}),
        {{"end", "period_end"}, {"val", "value_usd"}, {"accn", "accession"}}),
    Typed2 = Table.TransformColumnTypes(Renamed, {{"ticker", type text}, {"fiscal_year", Int64.Type}, {"period_end", type date},
        {"metric", type text}, {"value_usd", type number}, {"xbrl_concept", type text}, {"form", type text},
        {"filed", type date}, {"accession", type text}, {"cik", type text}}),
    // 7. EDGAR folder of the filing behind every value, so each number can be traced to its report
    Final = Table.AddColumn(Typed2, "filing_url", each "https://www.sec.gov/Archives/edgar/data/" & [cik] & "/"
        & Text.Remove([accession], "-") & "/", type text)
in
    Final


// ---------- fact_metal_prices ----------
// World Bank Pink Sheet: monthly gold, copper and silver prices (nominal US dollars), 2016-2025.
let
    Source = Excel.Workbook(Web.Contents("https://thedocs.worldbank.org", [RelativePath = WorldBankFile]), null, true),
    Sheet = Source{[Item = "Monthly Prices", Kind = "Sheet"]}[Data],
    Headers = Table.PromoteHeaders(Table.Skip(Sheet, 4), [PromoteAllScalars = true]),
    Renamed = Table.RenameColumns(Headers, {{Table.ColumnNames(Headers){0}, "period"}}),
    Kept = Table.SelectColumns(Renamed, {"period", "Gold", "Copper", "Silver"}),
    Months = Table.SelectRows(Kept, each [period] <> null and Text.Contains(Text.From([period]), "M")),
    Long = Table.UnpivotOtherColumns(Months, {"period"}, "metal", "price_usd"),
    Numbers = Table.SelectRows(Long, each Value.Is([price_usd], type number)),
    MonthStart = Table.AddColumn(Numbers, "month_start", each
        #date(Number.From(Text.BeforeDelimiter([period], "M")), Number.From(Text.AfterDelimiter([period], "M")), 1), type date),
    Unit = Table.AddColumn(MonthStart, "unit", each if [metal] = "Copper" then "$/mt" else "$/troy oz", type text),
    Kept2 = Table.SelectColumns(Unit, {"month_start", "metal", "unit", "price_usd"}),
    Typed = Table.TransformColumnTypes(Kept2, {{"metal", type text}, {"price_usd", type number}}),
    WithYear = Table.AddColumn(Typed, "year", each Date.Year([month_start]), Int64.Type),
    // same years as the company data
    Final = Table.SelectRows(WithYear, each [year] >= 2016 and [year] <= 2025)
in
    Final


// ---------- dim_company ----------
// Same list as data\companies.csv
let
    Source = #table(type table [ticker = text, company = text, segment = text, primary_metal = text, hq_country = text,
        reporting_standard = text, sort_order = Int64.Type, note = text], {
        {"NEM", "Newmont", "Gold miner", "Gold", "United States", "US GAAP", 1, ""},
        {"B", "Barrick Mining", "Gold miner", "Gold", "Canada", "IFRS", 2, "Renamed from Barrick Gold in 2025"},
        {"AEM", "Agnico Eagle Mines", "Gold miner", "Gold", "Canada", "IFRS", 3, ""},
        {"KGC", "Kinross Gold", "Gold miner", "Gold", "Canada", "IFRS", 4, ""},
        {"GFI", "Gold Fields", "Gold miner", "Gold", "South Africa", "IFRS", 5, ""},
        {"AU", "AngloGold Ashanti", "Gold miner", "Gold", "United Kingdom", "IFRS", 6, "Two SEC registrants: Ltd (to 2022) and plc (from 2023)"},
        {"AGI", "Alamos Gold", "Gold miner", "Gold", "Canada", "IFRS", 7, ""},
        {"IAG", "IAMGOLD", "Gold miner", "Gold", "Canada", "IFRS", 8, ""},
        {"FCX", "Freeport-McMoRan", "Copper miner", "Copper", "United States", "US GAAP", 9, ""},
        {"SCCO", "Southern Copper", "Copper miner", "Copper", "United States", "US GAAP", 10, ""},
        {"HBM", "Hudbay Minerals", "Copper miner", "Copper", "Canada", "IFRS", 11, ""},
        {"BHP", "BHP Group", "Diversified major", "Copper", "Australia", "IFRS", 12, "Fiscal year ends 30 June"},
        {"RIO", "Rio Tinto", "Diversified major", "Copper", "United Kingdom", "IFRS", 13, ""},
        {"WPM", "Wheaton Precious Metals", "Royalty & streaming", "Gold", "Canada", "IFRS", 14, ""},
        {"FNV", "Franco-Nevada", "Royalty & streaming", "Gold", "Canada", "IFRS", 15, ""},
        {"RGLD", "Royal Gold", "Royalty & streaming", "Gold", "United States", "US GAAP", 16, "Fiscal year ended 30 June until 2022"}}),
    Label = Table.AddColumn(Source, "company_label", each [company] & " (" & [ticker] & ")", type text)
in
    Label


// ---------- dim_metric ----------
let
    Source = #table(type table [metric = text, statement = text, sort_order = Int64.Type], {
        {"Revenue", "Income statement", 1}, {"Profit before tax", "Income statement", 2},
        {"Net income", "Income statement", 3}, {"Depreciation & amortization", "Income statement", 4},
        {"Operating cash flow", "Cash flow", 5}, {"Capex", "Cash flow", 6}, {"Dividends paid", "Cash flow", 7},
        {"Total assets", "Balance sheet", 8}, {"Cash", "Balance sheet", 9}, {"Total debt", "Balance sheet", 10},
        {"Shareholders' equity", "Balance sheet", 11}})
in
    Source
