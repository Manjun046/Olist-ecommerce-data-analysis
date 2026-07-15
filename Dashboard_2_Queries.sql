-- ==========================================================
-- Dashboard 2 : Product & Customer Insights
-- Project : Olist E-Commerce Data Analysis
-- ==========================================================

-- ==========================================================
-- Revenue by Product Category
-- ==========================================================

SELECT
trans.string_field_1 AS Category_Name,
ROUND(SUM(ord_items.price),2) AS Total_Revenue

FROM `myprojctexample.Olist_analysis.products` AS products

JOIN `myprojctexample.Olist_analysis.order_items` AS ord_items
ON products.product_id=ord_items.product_id

JOIN `myprojctexample.Olist_analysis.category_translation` AS trans
ON products.product_category_name=trans.string_field_0

GROUP BY Category_Name
ORDER BY Total_Revenue DESC;


-- ==========================================================
-- Revenue by Payment Type
-- ==========================================================

SELECT
payment_type,
ROUND(SUM(payment_value),2) AS Total_Revenue

FROM `myprojctexample.Olist_analysis.payments`

GROUP BY payment_type

ORDER BY Total_Revenue DESC;


-- ==========================================================
-- Top 10 Sellers by Revenue
-- ==========================================================

SELECT
seller_id,
ROUND(SUM(price),2) AS Total_Revenue

FROM `myprojctexample.Olist_analysis.order_items`

GROUP BY seller_id

ORDER BY Total_Revenue DESC

LIMIT 10;


-- ==========================================================
-- Review Score Distribution
-- ==========================================================

SELECT
review_score,
COUNT(review_id) AS Number_of_Reviews

FROM `myprojctexample.Olist_analysis.reviews`

GROUP BY review_score

ORDER BY review_score DESC;


-- ==========================================================
-- Average Review Score by Product Category
-- ==========================================================

SELECT
trans.string_field_1 AS Category_Name,
COUNT(review.review_id) AS Total_Reviews,
ROUND(AVG(review.review_score),2) AS Avg_Review_Score

FROM `myprojctexample.Olist_analysis.products` AS products

JOIN `myprojctexample.Olist_analysis.order_items` AS ord_items
ON products.product_id=ord_items.product_id

JOIN `myprojctexample.Olist_analysis.reviews` AS review
ON ord_items.order_id=review.order_id

JOIN `myprojctexample.Olist_analysis.category_translation` AS trans
ON products.product_category_name=trans.string_field_0

GROUP BY Category_Name

HAVING COUNT(review.review_id)>=50

ORDER BY Avg_Review_Score DESC;