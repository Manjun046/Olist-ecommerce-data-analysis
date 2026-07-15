-- ==========================================================
-- Olist E-Commerce Advanced SQL Portfolio
-- Platform: Google BigQuery
-- Project: Olist E-Commerce Data Analysis
--
-- This file showcases advanced SQL techniques used in the project:
-- CTEs, window functions, ranking, CASE WHEN, HAVING,
-- date functions, conditional aggregation, and joins.
-- ==========================================================


-- ==========================================================
-- 1. Monthly Running Revenue
-- Business question:
-- How does cumulative revenue grow month by month?
-- Concepts: CTE, SUM() OVER(), window frame
-- ==========================================================

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(DATE(o.order_purchase_timestamp), MONTH) AS month,
        ROUND(SUM(p.payment_value), 2) AS monthly_revenue
    FROM `myprojctexample.Olist_analysis.orders` AS o
    JOIN `myprojctexample.Olist_analysis.payments` AS p
        ON o.order_id = p.order_id
    GROUP BY month
)

SELECT
    month,
    monthly_revenue,
    ROUND(
        SUM(monthly_revenue) OVER (
            ORDER BY month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ),
        2
    ) AS running_revenue
FROM monthly_revenue
ORDER BY month;


-- ==========================================================
-- 2. Three-Month Moving Average Revenue
-- Business question:
-- What is the rolling three-month average revenue trend?
-- Concepts: CTE, AVG() OVER(), window frame
-- ==========================================================

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(DATE(o.order_purchase_timestamp), MONTH) AS month,
        ROUND(SUM(p.payment_value), 2) AS monthly_revenue
    FROM `myprojctexample.Olist_analysis.orders` AS o
    JOIN `myprojctexample.Olist_analysis.payments` AS p
        ON o.order_id = p.order_id
    GROUP BY month
)

SELECT
    month,
    monthly_revenue,
    ROUND(
        AVG(monthly_revenue) OVER (
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS three_month_moving_average
FROM monthly_revenue
ORDER BY month;


-- ==========================================================
-- 3. Customer Retention by Months After First Purchase
-- Business question:
-- How many customers returned after their first purchase month?
-- Concepts: DISTINCT, CTEs, MIN() OVER(), DATE_DIFF()
--
-- Note:
-- In the Olist orders table, customer_id is generally unique
-- per order. This query still demonstrates the retention pattern.
-- ==========================================================

WITH customer_months AS (
    SELECT DISTINCT
        customer_id,
        DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS purchase_month
    FROM `myprojctexample.Olist_analysis.orders`
),

customer_first_purchase AS (
    SELECT
        customer_id,
        purchase_month,
        MIN(purchase_month) OVER (
            PARTITION BY customer_id
        ) AS first_purchase_month
    FROM customer_months
),

retention_activity AS (
    SELECT
        customer_id,
        purchase_month,
        first_purchase_month,
        DATE_DIFF(
            purchase_month,
            first_purchase_month,
            MONTH
        ) AS months_after_first_purchase
    FROM customer_first_purchase
)

SELECT
    months_after_first_purchase,
    COUNT(DISTINCT customer_id) AS retained_customers
FROM retention_activity
WHERE months_after_first_purchase > 0
GROUP BY months_after_first_purchase
ORDER BY months_after_first_purchase;


-- ==========================================================
-- 4. Customer Segmentation by Total Spend
-- Business question:
-- Which customers are high, medium, or low value?
-- Concepts: CTE, JOIN, SUM(), CASE WHEN
-- ==========================================================

WITH customer_spend AS (
    SELECT
        o.customer_id,
        ROUND(SUM(p.payment_value), 2) AS total_spend
    FROM `myprojctexample.Olist_analysis.orders` AS o
    JOIN `myprojctexample.Olist_analysis.payments` AS p
        ON o.order_id = p.order_id
    GROUP BY o.customer_id
)

SELECT
    customer_id,
    total_spend,
    CASE
        WHEN total_spend > 5000 THEN 'High Value'
        WHEN total_spend BETWEEN 2000 AND 5000 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS customer_segment
FROM customer_spend
ORDER BY total_spend DESC;


-- ==========================================================
-- 5. Best-Selling Product in Each Category
-- Business question:
-- Which product sold the most units within each category?
-- Concepts: CTE, ROW_NUMBER(), PARTITION BY
-- ==========================================================

WITH product_sales AS (
    SELECT
        pr.product_category_name,
        oi.product_id,
        COUNT(oi.order_item_id) AS units_sold
    FROM `myprojctexample.Olist_analysis.products` AS pr
    JOIN `myprojctexample.Olist_analysis.order_items` AS oi
        ON pr.product_id = oi.product_id
    WHERE pr.product_category_name IS NOT NULL
    GROUP BY
        pr.product_category_name,
        oi.product_id
),

ranked_products AS (
    SELECT
        product_category_name,
        product_id,
        units_sold,
        ROW_NUMBER() OVER (
            PARTITION BY product_category_name
            ORDER BY units_sold DESC, product_id
        ) AS product_rank
    FROM product_sales
)

SELECT
    product_category_name,
    product_id,
    units_sold
FROM ranked_products
WHERE product_rank = 1
ORDER BY units_sold DESC;


-- ==========================================================
-- 6. Top Three Products in Each Category
-- Business question:
-- What are the top three products by units sold in every category?
-- Concepts: CTE, DENSE_RANK(), PARTITION BY
-- ==========================================================

WITH product_sales AS (
    SELECT
        pr.product_category_name,
        oi.product_id,
        COUNT(oi.order_item_id) AS units_sold
    FROM `myprojctexample.Olist_analysis.products` AS pr
    JOIN `myprojctexample.Olist_analysis.order_items` AS oi
        ON pr.product_id = oi.product_id
    WHERE pr.product_category_name IS NOT NULL
    GROUP BY
        pr.product_category_name,
        oi.product_id
),

ranked_products AS (
    SELECT
        product_category_name,
        product_id,
        units_sold,
        DENSE_RANK() OVER (
            PARTITION BY product_category_name
            ORDER BY units_sold DESC
        ) AS sales_rank
    FROM product_sales
)

SELECT
    product_category_name,
    product_id,
    units_sold,
    sales_rank
FROM ranked_products
WHERE sales_rank <= 3
ORDER BY
    product_category_name,
    sales_rank,
    product_id;


-- ==========================================================
-- 7. Revenue Contribution by Payment Type
-- Business question:
-- What percentage of total revenue comes from each payment type?
-- Concepts: CTE, SUM() OVER(), SAFE_DIVIDE()
-- ==========================================================

WITH payment_revenue AS (
    SELECT
        payment_type,
        ROUND(SUM(payment_value), 2) AS revenue
    FROM `myprojctexample.Olist_analysis.payments`
    GROUP BY payment_type
)

SELECT
    payment_type,
    revenue,
    ROUND(
        SAFE_DIVIDE(
            revenue * 100.0,
            SUM(revenue) OVER ()
        ),
        2
    ) AS revenue_contribution_pct
FROM payment_revenue
ORDER BY revenue DESC;


-- ==========================================================
-- 8. Monthly Cancellation Rate
-- Business question:
-- What percentage of orders were cancelled each month?
-- Concepts: COUNTIF(), SAFE_DIVIDE(), DATE_TRUNC()
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS month,
    COUNT(order_id) AS total_orders,
    COUNTIF(order_status = 'canceled') AS cancelled_orders,
    ROUND(
        SAFE_DIVIDE(
            COUNTIF(order_status = 'canceled') * 100.0,
            COUNT(order_id)
        ),
        2
    ) AS cancellation_rate_pct
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY month
ORDER BY month;


-- ==========================================================
-- 9. Monthly Average Delivery Time
-- Business question:
-- How many days does delivery take on average each month?
-- Concepts: DATE_DIFF(), AVG(), DATE_TRUNC()
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS month,
    COUNT(order_id) AS delivered_orders,
    ROUND(
        AVG(
            DATE_DIFF(
                DATE(order_delivered_customer_date),
                DATE(order_purchase_timestamp),
                DAY
            )
        ),
        2
    ) AS avg_delivery_days
FROM `myprojctexample.Olist_analysis.orders`
WHERE order_status = 'delivered'
GROUP BY month
ORDER BY month;


-- ==========================================================
-- 10. Top 10 Customers by Total Spend
-- Business question:
-- Which customers generated the highest payment value?
-- Concepts: JOIN, SUM(), GROUP BY, LIMIT
-- ==========================================================

SELECT
    o.customer_id,
    ROUND(SUM(p.payment_value), 2) AS total_spend
FROM `myprojctexample.Olist_analysis.orders` AS o
JOIN `myprojctexample.Olist_analysis.payments` AS p
    ON o.order_id = p.order_id
GROUP BY o.customer_id
ORDER BY total_spend DESC
LIMIT 10;


-- ==========================================================
-- 11. Customers With Multiple Orders
-- Business question:
-- Which customer IDs are linked to more than one order?
-- Concepts: GROUP BY, HAVING
--
-- Note:
-- This may return no rows because Olist customer_id is usually
-- unique per order. The result itself is a valid data finding.
-- ==========================================================

SELECT
    customer_id,
    COUNT(order_id) AS order_count
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY customer_id
HAVING COUNT(order_id) > 1
ORDER BY order_count DESC;


-- ==========================================================
-- 12. Average Review Score by Product Category
-- Business question:
-- Which categories have the highest customer satisfaction?
-- Concepts: Multiple JOINs, AVG(), HAVING
--
-- Only categories with at least 50 reviews are included.
-- ==========================================================

SELECT
    trans.string_field_1 AS category_name,
    COUNT(r.review_id) AS total_reviews,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM `myprojctexample.Olist_analysis.products` AS pr
JOIN `myprojctexample.Olist_analysis.order_items` AS oi
    ON pr.product_id = oi.product_id
JOIN `myprojctexample.Olist_analysis.reviews` AS r
    ON oi.order_id = r.order_id
JOIN `myprojctexample.Olist_analysis.category_translation` AS trans
    ON pr.product_category_name = trans.string_field_0
GROUP BY category_name
HAVING COUNT(r.review_id) >= 50
ORDER BY avg_review_score DESC;


-- ==========================================================
-- 13. Top Categories by Number of Items Sold
-- Business question:
-- Which product categories are ordered most frequently?
-- Concepts: Multiple JOINs, COUNT(), GROUP BY
-- ==========================================================

SELECT
    trans.string_field_1 AS category_name,
    COUNT(oi.order_item_id) AS items_sold
FROM `myprojctexample.Olist_analysis.products` AS pr
JOIN `myprojctexample.Olist_analysis.order_items` AS oi
    ON pr.product_id = oi.product_id
JOIN `myprojctexample.Olist_analysis.category_translation` AS trans
    ON pr.product_category_name = trans.string_field_0
GROUP BY category_name
ORDER BY items_sold DESC
LIMIT 10;


-- ==========================================================
-- 14. Monthly Revenue Growth Rate
-- Business question:
-- How much did revenue grow or decline compared with the prior month?
-- Concepts: CTE, LAG(), SAFE_DIVIDE()
-- ==========================================================

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC(DATE(o.order_purchase_timestamp), MONTH) AS month,
        ROUND(SUM(p.payment_value), 2) AS monthly_revenue
    FROM `myprojctexample.Olist_analysis.orders` AS o
    JOIN `myprojctexample.Olist_analysis.payments` AS p
        ON o.order_id = p.order_id
    GROUP BY month
),

revenue_with_previous_month AS (
    SELECT
        month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (
            ORDER BY month
        ) AS previous_month_revenue
    FROM monthly_revenue
)

SELECT
    month,
    monthly_revenue,
    previous_month_revenue,
    ROUND(
        SAFE_DIVIDE(
            monthly_revenue - previous_month_revenue,
            previous_month_revenue
        ) * 100,
        2
    ) AS monthly_growth_pct
FROM revenue_with_previous_month
ORDER BY month;


-- ==========================================================
-- 15. Top 10 Sellers by Revenue
-- Business question:
-- Which sellers generated the highest product revenue?
-- Concepts: SUM(), GROUP BY, ORDER BY, LIMIT
-- ==========================================================

SELECT
    seller_id,
    ROUND(SUM(price), 2) AS total_revenue
FROM `myprojctexample.Olist_analysis.order_items`
GROUP BY seller_id
ORDER BY total_revenue DESC
LIMIT 10;
