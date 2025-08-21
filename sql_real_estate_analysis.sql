-- Анализ времени активности объявлений
WITH limits AS (
    -- СТЕ для определения аномальных значений (выбросов) по значению перцентилей
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    -- СТЕ для нахождения id объявлений, которые не содержат выбросы
    SELECT f.id
    FROM real_estate.flats f  
    WHERE 
        f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
),
filtered_posts AS (
    -- СТЕ для вывода нужных объявлений без аномальных значений
    SELECT 
        a.id,
        a.days_exposition,
        a.last_price,
        f.city_id,
        f.type_id,
        f.total_area,
        f.rooms,
        f.ceiling_height,
        f.floor,
        f.balcony
    FROM real_estate.advertisement a
    LEFT JOIN real_estate.flats f USING (id)
    WHERE a.id IN (SELECT * FROM filtered_id) AND f.type_id = 'F8EM' -- id города
),
categorized_posts AS (
    -- СТЕ для разделения объявлений по городу и количеству дней
    SELECT *,
        CASE 
            WHEN c.city_id = (SELECT city_id FROM real_estate.city WHERE city = 'Санкт-Петербург') THEN 'Санкт-Петербург' -- поиск кода Санкт-Петербурга
            ELSE 'ЛенОбл'
        END AS region,
        CASE 
	        WHEN days_exposition IS NULL
	        THEN 'Активное объявление'
            WHEN days_exposition BETWEEN 1 AND 30 THEN 'Месяц' 
            WHEN days_exposition BETWEEN 31 AND 90 THEN 'Квартал'
            WHEN days_exposition BETWEEN 91 AND 180 THEN 'Полгода'
            ELSE 'Больше полугода'
        END AS days_activity
    FROM filtered_posts fp
    LEFT JOIN real_estate.city c USING (city_id)
),
final_summary AS (
    -- СТЕ для основных подсчетов
    SELECT 
        region, 
        days_activity, 
        COUNT(*) AS total_posts, 
        AVG(last_price::NUMERIC / total_area) AS avg_price_per_sqm, 
        AVG(total_area) AS avg_total_area, 
        PERCENTILE_CONT(0.5) within group (ORDER BY rooms) AS median_rooms, 
        PERCENTILE_CONT(0.5) within group (ORDER BY ceiling_height) AS median_ceiling_height,
        COUNT(*) FILTER (WHERE rooms = 0)::numeric / COUNT(*) AS studio_share -- подсчет доли квартир с 0 комнат (студии)
        FROM categorized_posts
    GROUP BY region, days_activity
)
-- Основной запрос с выводом значений и  их округлением для лучшей читабельности
SELECT region,
days_activity,
total_posts,
ROUND(avg_price_per_sqm::NUMERIC, 2) AS avg_price_per_sqm,
ROUND(avg_total_area::NUMERIC, 2) AS avg_total_area,
median_rooms,
ROUND(median_ceiling_height::NUMERIC, 2) AS median_ceiling_height,
ROUND(studio_share::NUMERIC, 2) AS studio_share
FROM final_summary;

-- Анализ сезонности объявлений
WITH limits AS (
    -- СТЕ для определения аномальных значений (выбросов) по значению перцентилей
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_id AS (
    -- СТЕ для нахождения id объявлений, которые не содержат выбросы
    SELECT f.id
    FROM real_estate.flats f  
    WHERE 
        f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
),
filtered_posts AS (
    -- СТЕ для вывода нужных объявлений без аномальных значений
    SELECT 
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.type_id
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    WHERE a.id IN (SELECT * FROM filtered_id) AND f.type_id = 'F8EM' -- id города
),
-- СТЕ для расчета даты продажи
sale_date AS (
SELECT ((days_exposition * INTERVAL '1 day') + first_day_exposition)::date AS sale_date,
id 
FROM filtered_posts),
-- СТЕ для расчета показателей публикаций объявлений
postings_info AS (
SELECT COUNT(id) AS total_months_posts,
COUNT(id)::NUMERIC / (SELECT COUNT(id) FROM filtered_posts) AS months_posts_share,
AVG(total_area) AS post_avg_total_area,
AVG(last_price::NUMERIC / total_area) AS post_avg_price_per_sqm,
EXTRACT(MONTH FROM first_day_exposition) AS posts_month_number
FROM filtered_posts 
GROUP BY posts_month_number),
-- СТЕ для расчета показателей продаж
month_category AS (
SELECT EXTRACT(MONTH FROM sale_date) AS month_number,
COUNT(fp.id)::NUMERIC / (SELECT COUNT(id) FROM filtered_posts WHERE days_exposition IS NOT NULL) AS months_sales_share,
COUNT(fp.id) AS total_months_sales,
AVG(total_area) AS avg_total_area,
AVG(last_price::NUMERIC / total_area) AS avg_price_per_sqm
FROM filtered_posts fp
LEFT join sale_date AS sd ON sd.id = fp.id
WHERE days_exposition IS NOT NULL
GROUP BY month_number)
-- Основной запрос
SELECT CASE month_number
        WHEN 1 THEN 'January'
        WHEN 2 THEN 'February'
        WHEN 3 THEN 'March'
        WHEN 4 THEN 'April'
        WHEN 5 THEN 'May'
        WHEN 6 THEN 'June'
        WHEN 7 THEN 'July'
        WHEN 8 THEN 'August'
        WHEN 9 THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END AS month_name,
rank() over (ORDER BY months_posts_share DESC) AS posts_rank,
rank() over (ORDER BY months_sales_share DESC) AS sales_rank,
total_months_posts,
ROUND(months_posts_share::NUMERIC, 2) AS months_posts_share,
total_months_sales,
ROUND(months_sales_share::NUMERIC, 2) AS months_sales_share,
ROUND(avg_total_area::NUMERIC, 2) AS avg_total_area,
ROUND(avg_price_per_sqm::NUMERIC, 2) AS avg_price_per_sqm
FROM month_category AS m
full join postings_info AS p ON m.month_number = p.posts_month_number
ORDER BY month_number;

-- Анализ рынка недвижимости Ленобласти
WITH limits AS (
    -- СТЕ для определения аномальных значений (выбросов) по значению перцентилей
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats),
filtered_id AS (
    -- СТЕ для нахождения id объявлений, которые не содержат выбросы
    SELECT f.id
    FROM real_estate.flats f  
    WHERE 
        f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
),
filtered_posts AS (
    -- СТЕ для вывода нужных объявлений без аномальных значений и исключения объявлений в Санкт-Петербурге
    SELECT 
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.city_id,
        c.city,
        f.total_area
    FROM real_estate.advertisement a
    LEFT JOIN real_estate.flats f ON a.id = f.id
    RIGHT join real_estate.city c ON c.city_id = f.city_id
    WHERE a.id IN (SELECT * FROM filtered_id) AND city != 'Санкт-Петербург'
),
-- СТЕ для расчета информации о проданным квартирах по населенным пунктам
sold_info AS (
SELECT city_id,
COUNT(id) FILTER(WHERE days_exposition IS NOT NULL) AS total_sold,
AVG(total_area) AS avg_sold_total_area,
SUM(last_price)::NUMERIC / SUM(total_area) AS avg_rub_per_m_sold,
AVG(days_exposition) AS avg_days_exposition
FROM filtered_posts
GROUP BY city_id),
-- СТЕ для расчета информации о непроданных квартирах по населенным пунктам
total_posted AS (
SELECT city_id,
COUNT(id) AS total_posts
FROM filtered_posts
GROUP BY city_id)
-- Основной запрос
SELECT city,
total_posts,
total_sold,
ROUND((total_sold::NUMERIC / total_posts), 2) AS sold_share,
ROUND(avg_days_exposition::NUMERIC, 2) AS avg_days_exposition,
ROUND(avg_sold_total_area::NUMERIC, 2) AS avg_sold_total_area,
ROUND(avg_rub_per_m_sold::NUMERIC, 2) AS avg_rub_per_m_sold
FROM sold_info si 
LEFT join total_posted tp ON tp.city_id = si.city_id
LEFT join real_estate.city c ON c.city_id = si.city_id
WHERE total_posts >= 50 -- только населенные пункты, в которых от 50 объявлений
ORDER BY sold_share DESC;