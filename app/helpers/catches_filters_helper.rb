module CatchesFiltersHelper
  def match_conditions_chip(path:, param:, value:, label:, active:, carry_params:)
    out = +%(<form method="get" action="#{ERB::Util.h(path)}" class="inline">)
    carry_params.each do |k, v|
      out << %(<input type="hidden" name="#{ERB::Util.h(k)}" value="#{ERB::Util.h(v)}">)
    end
    submit_value = active ? "" : value
    out << %(<input type="hidden" name="#{ERB::Util.h(param)}" value="#{ERB::Util.h(submit_value)}">)
    out << %(<input type="hidden" name="mc" value="open">)
    cls = active ? "bg-blue-600 border-blue-500 text-white" : "bg-slate-800 border-slate-700 text-slate-200"
    out << %(<button type="submit" class="px-3 py-1 rounded-full text-sm border #{cls}" data-test="chip-#{ERB::Util.h(param)}-#{ERB::Util.h(value)}">#{ERB::Util.h(label)}</button>)
    out << "</form>"
    out.html_safe
  end
end
