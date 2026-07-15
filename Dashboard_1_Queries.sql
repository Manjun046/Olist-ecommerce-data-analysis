-- ==========================================================
-- Dashboard 1 : Executive Overview
-- Project : Olist E-Commerce Data Analysis
-- ==========================================================

-- ==========================================================
-- Monthly Revenue
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
    ROUND(SUM(payment_value),2) AS Revenue
FROM `myprojctexample.Olist_analysis.orders` AS orders
JOIN `myprojctexample.Olist_analysis.payments` AS pays
ON orders.order_id = pays.order_id
GROUP BY Month
ORDER BY Month;


-- ==========================================================
-- Monthly Total Orders
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
    COUNT(order_id) AS Total_Orders
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY Month
ORDER BY Month;


-- ==========================================================
-- Monthly Cancellation Rate
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
    ROUND(
        COUNTIF(order_status='canceled')*100.0/
        COUNT(order_id),2
    ) AS Cancellation_Rate
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY Month
ORDER BY Month;


-- ==========================================================
-- Monthly Average Delivery Days
-- ==========================================================

SELECT
    DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
    ROUND(
        AVG(
            DATE_DIFF(
                DATE(order_delivered_customer_date),
                DATE(order_purchase_timestamp),
                DAY
            )
        ),2
    ) AS Avg_Delivery_Days
FROM `myprojctexample.Olist_analysis.orders`
WHERE order_status='delivered'
GROUP BY Month
ORDER BY Month;


-- ==========================================================
-- Final Dashboard Dataset
-- ==========================================================

CREATE OR REPLACE TABLE `myprojctexample.Olist_analysis.dashboard_dataset` AS

WITH Monthly_revenue AS
(
SELECT
DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
ROUND(SUM(payment_value),2) AS Revenue
FROM `myprojctexample.Olist_analysis.orders` AS orders
JOIN `myprojctexample.Olist_analysis.payments` AS pays
ON orders.order_id=pays.order_id
GROUP BY Month
),

Total_Orders AS
(
SELECT
DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
COUNT(order_id) AS Total_Orders
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY Month
),

Cancellation_rates AS
(
SELECT
DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
ROUND(
COUNTIF(order_status='canceled')*100.0/
COUNT(order_id),2
) AS Cancellation_Rate
FROM `myprojctexample.Olist_analysis.orders`
GROUP BY Month
),

Average_delivery AS
(
SELECT
DATE_TRUNC(DATE(order_purchase_timestamp), MONTH) AS Month,
ROUND(
AVG(
DATE_DIFF(
DATE(order_delivered_customer_date),
DATE(order_purchase_timestamp),
DAY)
),2) AS Avg_Delivery_Days
FROM `myprojctexample.Olist_analysis.orders`
WHERE order_status='delivered'
GROUP BY Month
)

SELECT
r.Month,
r.Revenue,
o.Total_Orders,
c.Cancellation_Rate,
d.Avg_Delivery_Days

FROM Monthly_revenue r

LEFT JOIN Total_Orders o
ON r.Month=o.Month

LEFT JOIN Cancellation_rates c
ON r.Month=c.Month

LEFT JOIN Average_delivery d
ON r.Month=d.Month

ORDER BY r.Month;