SELECT * FROM dim_customer;

SELECT * FROM dim_product;

SELECT * FROM fact_gross_price;

SELECT * FROM fact_manufacturing_cost;

SELECT * FROM fact_pre_invoice_deductions;

SELECT * FROM fact_sales_monthly;

/*
1. Provide the list of markets in which customer "Atliq Exclusive" operates its business in the APAC region.
*/

SELECT DISTINCT market 
FROM dim_customer
WHERE customer = 'Atliq Exclusive' AND region = 'APAC';

/*
2. What is the percentage of unique product increase in 2021 vs. 2020? The final output contains these fields,
unique_products_2020, unique_products_2021, percentage_chg
*/

WITH cte_2020 AS (
	SELECT COUNT(DISTINCT (product_code)) AS unique_products_2020
    FROM fact_sales_monthly
    WHERE fiscal_year = 2020
),
cte_2021 AS (
	SELECT COUNT(DISTINCT (product_code)) AS unique_products_2021
    FROM fact_sales_monthly
    WHERE fiscal_year = 2021
)

SELECT 
	cte_2020.unique_products_2020,
    cte_2021.unique_products_2021,
    CONCAT(ROUND((unique_products_2021 - unique_products_2020) / unique_products_2020 * 100, 2), '%') AS percentage_chg
FROM cte_2020, cte_2021;

/*
3. Provide a report with all the unique product counts for each segment and sort them in descending order of product counts. 
The final output contains 2 fields, segment, product_count
*/
SELECT 
	segment,
    COUNT(DISTINCT (product_code)) AS product_count
FROM dim_product
GROUP BY segment
ORDER BY product_count DESC;

/*
4. Follow-up: Which segment had the most increase in unique products in 2021 vs 2020? The final output contains these fields,
segment, product_count_2020, product_count_2021, difference
*/

WITH fy20 AS (
	SELECT 
		segment,
		COUNT(DISTINCT (fm.product_code)) AS seg_2020
	FROM fact_sales_monthly fm
	LEFT JOIN dim_product dp
	ON fm.product_code = dp.product_code
	WHERE fiscal_year = 2020
	GROUP BY segment
),

fy21 AS (
	SELECT 
		segment,
		COUNT(DISTINCT (fm.product_code)) AS seg_2021
	FROM fact_sales_monthly fm
	LEFT JOIN dim_product dp
	ON fm.product_code = dp.product_code
	WHERE fiscal_year = 2021
	GROUP BY segment
)

SELECT 
	fy20.segment,
    seg_2020 AS product_count_2020,
    seg_2021 AS product_count_2021,
	seg_2021 - seg_2020 AS difference
FROM fy21
JOIN fy20 
ON fy21.segment = fy20.segment
ORDER BY difference DESC;

/*
5. Get the products that have the highest and lowest manufacturing costs.
The final output should contain these fields, product_code, product, manufacturing_cost
*/

SELECT 
    fmc.product_code,
    dp.product,
    fmc.manufacturing_cost AS manufacturing_cost
FROM
    fact_manufacturing_cost fmc
        JOIN
    dim_product dp ON fmc.product_code = dp.product_code
WHERE
    fmc.manufacturing_cost = (SELECT 
            MAX(manufacturing_cost)
        FROM
            fact_manufacturing_cost)
        OR fmc.manufacturing_cost = (SELECT 
            MIN(manufacturing_cost)
        FROM
            fact_manufacturing_cost)
ORDER BY manufacturing_cost DESC;

/*
6. Generate a report which contains the top 5 customers who received an average high pre_invoice_discount_pct 
for the fiscal year 2021 and in the Indian market. The final output contains these fields,
customer_code, customer, average_discount_percentage
*/

SELECT 
	fid.customer_code,
    dc.customer,
    ROUND(AVG(pre_invoice_discount_pct) * 100, 2) AS average_discount_percentage
FROM fact_pre_invoice_deductions fid
JOIN dim_customer dc
ON fid.customer_code = dc.customer_code
WHERE market = 'India' AND fid.fiscal_year = 2021
GROUP BY customer, fid.customer_code
ORDER BY average_discount_percentage DESC
LIMIT 5;

/*
7. Get the complete report of the Gross sales amount for the customer “Atliq Exclusive” for each month. 
This analysis helps to get an idea of low and high-performing months and take strategic decisions.
The final report contains these columns: Month, Year, Gross sales Amount
*/

WITH gross_table AS (
	SELECT
		date,
        fm.customer_code,
        fp.fiscal_year,
        gross_price * sold_quantity AS gross_sales
	FROM 
		fact_gross_price fp
	JOIN
		fact_sales_monthly fm
			ON
		fp.product_code = fm.product_code
			AND
		fp.fiscal_year = fm.fiscal_year
),

customer AS (
	SELECT 
		date,
        dc.customer_code,
        gross_sales
	FROM 
		gross_table gt
    JOIN
		dim_customer dc
			ON
		gt.customer_code = dc.customer_code
	WHERE 
		customer = 'Atliq Exclusive'
)

SELECT 
	MONTH(date) AS Month,
    YEAR(date) AS Year,
    ROUND(SUM(gross_sales) / 1000000, 2) AS Gross_sales_amount
FROM 
	customer
GROUP BY Month, Year;

/*
8. In which quarter of 2020, got the maximum total_sold_quantity? The final output contains these fields 
sorted by the total_sold_quantity, Quarter, total_sold_quantity
*/

SELECT 
    CASE 
		WHEN MONTH(date) BETWEEN 09 AND 11 THEN 'Q1'
        WHEN MONTH(date) IN (12, 01, 02) THEN 'Q2'
        WHEN MONTH(date) BETWEEN 03 AND 05 THEN 'Q3'
        WHEN MONTH(date) BETWEEN 06 AND 08 THEN 'Q4'
	END AS Quarter,
    SUM(sold_quantity) AS total_sold_quantity
    FROM fact_sales_monthly
    WHERE fiscal_year = 2020
    GROUP BY Quarter
    ORDER BY total_sold_quantity DESC;
    
/*
9. Which channel helped to bring more gross sales in the fiscal year 2021 and the percentage of contribution? 
The final output contains these fields, channel, gross_sales_mln, percentage
*/

WITH gross_sales_table AS (
	SELECT 
		customer_code,
        gross_price * sold_quantity AS gross_sales_mln
	FROM 
		fact_gross_price fp
	JOIN
		fact_sales_monthly fm
			ON
		fp.product_code = fm.product_code
			AND
		fp.fiscal_year = fm.fiscal_year
	WHERE
		fp.fiscal_year = 2021
),

channel_table AS (
	SELECT 
		channel,
        ROUND(SUM(gross_sales_mln / 1000000), 2) AS gross_sales_mln
	FROM 
		gross_sales_table gt
	JOIN
		dim_customer dc
			ON
		gt.customer_code =  dc.customer_code
	GROUP BY channel
),
total_sum AS (
	SELECT
		SUM(gross_sales_mln) AS SUM_
	FROM
		channel_table
)

SELECT 
	ct.*,
    CONCAT(ROUND(ct.gross_sales_mln * 100 / ts.SUM_ , 2), "%") AS percentage
FROM 
	channel_table ct, total_sum ts
ORDER BY percentage DESC;

/*
10. Get the Top 3 products in each division that have a high total_sold_quantity in the fiscal_year 2021? 
The final output contains these fields, division, product_code, product, total_sold_quantity, rank_order
*/

WITH product AS (
	SELECT
		dp.division,
		fm.product_code,
        dp.product,
        SUM(fm.sold_quantity) AS total_sold_quantity
	FROM 
		fact_sales_monthly fm
	JOIN
		dim_product dp
			ON
		fm.product_code = dp.product_code
	WHERE fm.fiscal_year = 2021
    GROUP BY fm.product_code, dp.division, dp.product
),

rank_ AS (
	SELECT
		*,
		RANK () OVER(PARTITION BY division ORDER BY total_sold_quantity DESC) AS rank_order 
	FROM product
)

SELECT * 
FROM rank_
WHERE rank_order < 4;