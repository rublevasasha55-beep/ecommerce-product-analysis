-- =========================================================
-- E-commerce Product Analysis
-- Анализ покупательского поведения
-- Диалект: PostgreSQL
-- =========================================================


-- 1. Количество завершённых заказов на одного пользователя
-- Смотрим распределение покупателей по частоте покупок

WITH user_orders AS (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS completed_orders
    FROM orders
    WHERE order_status = 'completed'
    GROUP BY user_id
)

SELECT
    completed_orders,
    COUNT(*) AS users
FROM user_orders
GROUP BY completed_orders
ORDER BY completed_orders;


-- 2. Доля повторных покупателей
-- Повторным считаем пользователя с двумя и более завершёнными заказами

WITH user_orders AS (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS completed_orders
    FROM orders
    WHERE order_status = 'completed'
    GROUP BY user_id
)

SELECT
    COUNT(*) AS buyers,
    COUNT(*) FILTER (
        WHERE completed_orders >= 2
    ) AS repeat_buyers,
    ROUND(
        (
            100.0
            * COUNT(*) FILTER (
                WHERE completed_orders >= 2
            )
            / COUNT(*)
        )::numeric,
        2
    ) AS repeat_rate_pct
FROM user_orders;


-- 3. Предыдущая покупка и интервал между заказами
-- LAG позволяет получить дату предыдущей покупки каждого пользователя
-- После этого рассчитываем интервал между последовательными заказами

WITH ordered_purchases AS (
    SELECT
        user_id,
        order_id,
        order_date,
        total_amount,
        LAG(order_date) OVER (
            PARTITION BY user_id
            ORDER BY order_date, order_id
        ) AS prev_order_date
    FROM orders
    WHERE order_status = 'completed'
),

purchase_intervals AS (
    SELECT
        user_id,
        order_id,
        order_date,
        prev_order_date,
        EXTRACT(
            EPOCH FROM (order_date - prev_order_date)
        ) / 86400.0 AS days_since_prev
    FROM ordered_purchases
    WHERE prev_order_date IS NOT NULL
)

SELECT
    COUNT(*) AS repeat_purchase_intervals,
    ROUND(
        AVG(days_since_prev)::numeric,
        2
    ) AS avg_days_between,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY days_since_prev
        )::numeric,
        2
    ) AS median_days_between
FROM purchase_intervals;


-- 4. Первая и вторая завершённая покупка пользователя
-- ROW_NUMBER задаёт порядковый номер заказа внутри истории пользователя
-- В итоговую выборку включаем только пользователей с повторной покупкой

WITH ranked_orders AS (
    SELECT
        user_id,
        order_id,
        order_date,
        total_amount,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY order_date, order_id
        ) AS order_number
    FROM orders
    WHERE order_status = 'completed'
),

first_second_orders AS (
    SELECT
        user_id,
        MAX(order_date) FILTER (
            WHERE order_number = 1
        ) AS first_order_date,
        MAX(order_date) FILTER (
            WHERE order_number = 2
        ) AS second_order_date,
        MAX(total_amount) FILTER (
            WHERE order_number = 1
        ) AS first_order_amount,
        MAX(total_amount) FILTER (
            WHERE order_number = 2
        ) AS second_order_amount
    FROM ranked_orders
    WHERE order_number <= 2
    GROUP BY user_id
)

SELECT
    user_id,
    first_order_date,
    second_order_date,
    ROUND(
        first_order_amount::numeric,
        2
    ) AS first_order_amount,
    ROUND(
        second_order_amount::numeric,
        2
    ) AS second_order_amount,
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    second_order_date - first_order_date
                )
            ) / 86400.0
        )::numeric,
        2
    ) AS days_to_second_purchase
FROM first_second_orders
WHERE second_order_date IS NOT NULL
ORDER BY days_to_second_purchase;


-- 5. Сегментация покупателей по количеству покупок
-- Разделяем пользователей на разовых, повторных и пользователей с 3+ заказами
-- Для каждого сегмента считаем число пользователей, GMV и средний GMV на пользователя

WITH user_orders AS (
    SELECT
        user_id,
        COUNT(DISTINCT order_id) AS completed_orders,
        SUM(total_amount) AS total_gmv
    FROM orders
    WHERE order_status = 'completed'
    GROUP BY user_id
),

segments AS (
    SELECT
        user_id,
        completed_orders,
        total_gmv,
        CASE
            WHEN completed_orders = 1
                THEN 'one-time buyer'
            WHEN completed_orders = 2
                THEN 'repeat buyer'
            ELSE '3+ orders'
        END AS buyer_segment
    FROM user_orders
)

SELECT
    buyer_segment,
    COUNT(*) AS users,
    ROUND(
        SUM(total_gmv)::numeric,
        2
    ) AS gmv,
    ROUND(
        AVG(total_gmv)::numeric,
        2
    ) AS avg_gmv_per_user,
    ROUND(
        (
            100.0
            * COUNT(*)
            / SUM(COUNT(*)) OVER ()
        )::numeric,
        2
    ) AS user_share_pct
FROM segments
GROUP BY buyer_segment
ORDER BY users DESC;
