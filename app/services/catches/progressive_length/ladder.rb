module Catches
  module ProgressiveLength
    # The ladder is a pure function of a set of catches: walk them oldest-first
    # and keep each fish that is STRICTLY longer than the last one kept. A
    # smaller or equal fish is a silent no-op — it neither joins the ladder nor
    # breaks it.
    #
    # Deriving from capture order (not arrival order) is what makes offline sync
    # correct: a catch logged offline can reach the server after a larger fish
    # while carrying an earlier captured_at_device, and it must still land at its
    # true rung. The consequence — a late big fish can invalidate the rungs above
    # it and lower a visible score — is intended, and is the only ordering that
    # doesn't reward a flaky connection.
    #
    # The (captured_at_device, id) sort key makes the result deterministic when
    # two catches share a timestamp.
    module Ladder
      module_function

      def call(catches)
        catches
          .sort_by { |c| [c.captured_at_device, c.id] }
          .each_with_object([]) do |candidate, rungs|
            rungs << candidate if rungs.empty? || candidate.length_inches > rungs.last.length_inches
          end
      end
    end
  end
end
