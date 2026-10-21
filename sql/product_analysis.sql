-- =========================================================
-- E-commerce Product Analysis
-- Анализ товаров и категорий
-- Диалект: PostgreSQL
-- =========================================================


-- 1. Помесячные метрики завершённых заказов
-- Считаем GMV, количество заказов, покупателей и средний чек

SELECT
    DATE_TRUNC('month', order_date)::date AS month,
    COUNT(DISTINCT order_id) AS completed_orders,
    COUNT(DISTINCT user_id) AS buyers,
    ROUND(SUM(total_amount)::numeric, 2) AS gmv,
    ROUND(AVG(total_amount)::numeric, 2) AS avg_order_value
FROM orders
WHERE order_status = 'completed'
  AND order_date < DATE '2025-11-01'
GROUP BY 1
ORDER BY 1;


-- 2. GMV и доля GMV по категориям товаров
-- Объединяем заказы, товарные позиции и справочник товаров
-- В расчёт включаем только завершённые заказы

WITH category_gmv AS (
    SELECT
        p.category,
        SUM(oi.item_total) AS gmv
    FROM order_items AS oi
    JOIN orders AS o
        ON oi.order_id = o.order_id
    JOIN products AS p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'completed'
    GROUP BY p.category
)

SELECT
    category,
    ROUND(gmv::numeric, 2) AS gmv,
    ROUND(
        (100.0 * gmv / SUM(gmv) OVER ())::numeric,
        2
    ) AS gmv_share_pct
FROM category_gmv
ORDER BY gmv DESC;


-- 3. Топ-3 товара по GMV внутри каждой категории
-- Сначала рассчитываем показатели каждого товара
-- Затем ранжируем товары отдельно внутри каждой категории

WITH product_metrics AS (
    SELECT
        p.category,
        p.product_id,
        p.product_name,
        SUM(oi.item_total) AS gmv,
        SUM(oi.quantity) AS units_sold,
        COUNT(DISTINCT oi.order_id) AS orders,
        COUNT(DISTINCT oi.user_id) AS buyers
    FROM order_items AS oi
    JOIN orders AS o
        ON oi.order_id = o.order_id
    JOIN products AS p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'completed'
    GROUP BY
        p.category,
        p.product_id,
        p.product_name
),

ranked_products AS (
    SELECT
        *,
        DENSE_RANK() OVER (
            PARTITION BY category
            ORDER BY gmv DESC
        ) AS gmv_rank
    FROM product_metrics
)

SELECT
    category,
    product_id,
    product_name,
    ROUND(gmv::numeric, 2) AS gmv,
    units_sold,
    orders,
    buyers,
    gmv_rank
FROM ranked_products
WHERE gmv_rank <= 3
ORDER BY category, gmv_rank, gmv DESC;


-- 4. Доля GMV Electronics, которую формируют топ-10 товаров
-- Проверяем, зависит ли GMV категории от небольшого числа лидирующих SKU

WITH electronics_products AS (
    SELECT
        p.product_id,
        p.product_name,
        SUM(oi.item_total) AS gmv
    FROM order_items AS oi
    JOIN orders AS o
        ON oi.order_id = o.order_id
    JOIN products AS p
        ON oi.product_id = p.product_id
    WHERE o.order_status = 'completed'
      AND p.category = 'Electronics'
    GROUP BY
        p.product_id,
        p.product_name
),

ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            ORDER BY gmv DESC
        ) AS rn
    FROM electronics_products
)

SELECT
    ROUND(SUM(gmv)::numeric, 2) AS electronics_gmv,
    ROUND(
        SUM(
            CASE
                WHEN rn <= 10 THEN gmv
                ELSE 0
            END
        )::numeric,
        2
    ) AS top10_gmv,
    ROUND(
        (
            100.0
            * SUM(
                CASE
                    WHEN rn <= 10 THEN gmv
                    ELSE 0
                END
            )
            / SUM(gmv)
        )::numeric,
        2
    ) AS top10_share_pct
FROM ranked;