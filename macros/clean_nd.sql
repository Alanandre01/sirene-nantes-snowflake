{% macro clean_nd(column_name) %}
    CASE
        WHEN TRIM({{ column_name }}) = '[ND]' THEN NULL
        WHEN TRIM({{ column_name }}) = ''     THEN NULL
        ELSE TRIM({{ column_name }})
    END
{% endmacro %}
