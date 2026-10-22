{% macro assert_no_deprecated_model_dependencies() %}
{#
  Fail compile/run if any model, test, analysis, or snapshot depends on a
  deprecated shim. Shims may only point at their canonical replacements.
  Remove this macro (or shrink the list) when shims are deleted.
#}
{% if execute %}
    {% set deprecated_model_names = ['fct_inv_sap', 'fct_inv_timing_overlay'] %}
    {% set deprecated_node_ids = [] %}
    {% for model_name in deprecated_model_names %}
        {% do deprecated_node_ids.append('model.' ~ project_name ~ '.' ~ model_name) %}
    {% endfor %}

    {% for node_id, node in graph.nodes.items() %}
        {% if node_id not in deprecated_node_ids
            and node.resource_type in ['model', 'test', 'analysis', 'snapshot'] %}
            {% for dep in node.depends_on.nodes %}
                {% if dep in deprecated_node_ids %}
                    {% set shim_name = dep.split('.')[-1] %}
                    {{ exceptions.raise_compiler_error(
                        'Deprecated model ref: '
                        ~ node.name
                        ~ ' ('
                        ~ node.resource_type
                        ~ ') depends on '
                        ~ shim_name
                        ~ '. Use fct_inv_sap_cd or fct_inv_timing_overlay_cd instead, or remove the shim.'
                    ) }}
                {% endif %}
            {% endfor %}
        {% endif %}
    {% endfor %}
{% endif %}
{% endmacro %}
