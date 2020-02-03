defimpl String.Chars, for: JustCurious.Game do
  @doc "string interpolated `game` prints the channel"
  @spec to_string(struct) :: String.t
  def to_string(game), do: game.channel
end

defmodule JustCurious.Game do
  import Exredis.Api
  import JustCurious.Helpers, only: [
    redis_list_from_struct: 1,
    string_map_to_atom_map: 1,
    jc_bot_id: 1
  ]

  @enforce_keys ~w(name team)a
  defstruct ~w(
    created_at name team channel state round chainlink
    start_timeout
    start_reminder
    start_reattempts
    submitted_timeout
    submitted_reminder
    nominated_timeout
    nominated_reminder
    nominated_reattempts
    answered_timeout
    answered_reminder
    answered_reattempts
  )a

  @moduledoc """
  A `JustCurious.Game` is a FSM made up that transition through `round`s that to handle game state changes.

  ## `transition`s
  1. start
  2. submitted
  3. nominated
  4. answered
  5. finish

  ## `round`s
  1. submitting
  2. nominating
  3. answering
  4. complete

  ## `state`s
  1. new    - start
  2. active - submitted, nominated, answered
  3. dead   - finish

  ## Anatomy of the Game
  Game state is tracked via a disposable Redis structure for preferences, participants, submissions, nominations, and answers

  ``` plaintext
  TXXX = Team, UXXX = User, 000.00X = Timestamp/Message UUID

  team:T123:game:some-game
    :players -> ["U111", "U222"]
    :spectators -> ["U555"]
    :invites -> ["U666"]
    :joins -> ["U333"]
    :name -> "Serene Desert"
    :state -> "new"
    :round -> "submitting"
    :invitiation_messages -> [000.001] # Keep track of invitation messages for updating
    :participant
           :U111 # hash
                :prompting -> "answer_confirmation" # prompt state tracking
                :unconfirmed_submission -> "What's your favorite color?"
                :submission -> "What's your favorite color?"
                :answer -> "Green"
                ...

    :submissions # sorted set
                :question-o-matic-1 -> 2 # a question-o-matic submitter with score
                :U111               -> 1 # or real user submitter
                :U222               -> 0

    :nominatables # hash
                 :000.001 -> U111 # nominatable message id and user id
                 :000.002 -> U222
    :nominations
                :upvotes
                          :U111
                               :target -> "000.002" # user 1 upvoted second nominatable
                               :reaction -> "heart" # with a heart reaction
                          :U222
                               :target -> "000.001"
                               :reaction -> "+1" # with a heart reaction
                :downvotes
                          :U111 -> "000.003"

  ```
  """

  @spec create(String.t, Map.t) :: %JustCurious.Game{}
  def create(team, opts \\ %{}) do
    name       = generate_name(team, :game)
    game_id    = name |> String.downcase |> String.replace(" ", "-")
    created_at = DateTime.utc_now |> DateTime.to_unix(:microseconds)

    new_game = %JustCurious.Game{
      team: team,
      name: name,
      channel: game_id,
      round: opts[:round],
      state: opts[:state] || :new,
      created_at: created_at,
      chainlink: 0
    } |> Map.merge(JustCurious.GameConfigs.get(opts[:config]))

    incr("team:#{team}:games_played")
    hmset("team:#{team}:game:#{game_id}", redis_list_from_struct(new_game))

    JustCurious.MessageQueue.deliver_at(new_game, "transition start", created_at + new_game.start_timeout)

    sadd("team:#{team}:games", game_id)
    (opts[:players] || []) |> Enum.each(&(add_participant(new_game, &1)))
    (opts[:joins] || []) |> Enum.each(&(add_participant(new_game, &1, :join)))
    (opts[:invites] || []) |> Enum.each(&(add_participant(new_game, &1, :invite)))
    (opts[:spectators] || []) |> Enum.each(&(add_participant(new_game, &1, :spectator)))

    hincrby("team:#{team}:game:#{game_id}", "chainlink", 0)

    find(team, game_id)
  end

  @spec find(String.t, String.t) :: %JustCurious.Game{}
  def find(team_id, game_id) do
    # TODO game does not exist
    game = struct(JustCurious.Game, string_map_to_atom_map(hgetall("team:#{team_id}:game:#{String.downcase("#{game_id}")}")))
    game
      |> Map.put(:participants, participants(game))
      |> Map.put(:players, players(game))
      |> Map.put(:spectators, spectators(game))
      |> Map.put(:invites, invites(game))
      |> Map.put(:joins, joins(game))
  end

  ## STATE/ROUND/CHAINLINK ##
  @spec get_state(%JustCurious.Game{}) :: atom
  def get_state(game) do
    hget("team:#{game.team}:game:#{game}", "state") |> String.to_atom
  end

  @spec set_state(%JustCurious.Game{}, atom) :: atom
  def set_state(game, state) do
    hset("team:#{game.team}:game:#{game}", "state", state)
    :"#{state}"
  end

  @spec get_round(%JustCurious.Game{}) :: atom
  def get_round(game), do: hget("team:#{game.team}:game:#{game}", "round") |> String.to_atom

  @spec set_round(%JustCurious.Game{}, atom) :: atom
  def set_round(game, new_round) do
    hset("team:#{game.team}:game:#{game}", "round", new_round)
    :"#{new_round}"
  end

  @spec get_chainlink(%JustCurious.Game{}) :: atom
  def get_chainlink(game), do: hget("team:#{game.team}:game:#{game}", "chainlink") |> String.to_integer

  @spec incr_chainlink(%JustCurious.Game{}) :: integer
  def incr_chainlink(game), do: hincrby("team:#{game.team}:game:#{game}", "chainlink", 1)

  ## TRANSITION HELPERS ##
  @spec new?(%JustCurious.Game{}) :: boolean
  def new?(game), do: get_state(game) == :new

  @spec started?(%JustCurious.Game{}) :: boolean
  def started?(game), do: not Enum.member?(~w(new dead)a, get_state(game))

  @spec submitting?(%JustCurious.Game{}) :: boolean
  def submitting?(game), do: get_round(game) == :submitting

  @spec nominating?(%JustCurious.Game{}) :: boolean
  def nominating?(game), do: get_round(game) == :nominating

  @spec answering?(%JustCurious.Game{}) :: boolean
  def answering?(game), do: get_round(game) == :answering

  @spec complete?(%JustCurious.Game{}) :: boolean
  def complete?(game), do: get_round(game) == :complete

  @spec ended?(%JustCurious.Game{}) :: boolean
  def ended?(game), do: get_state(game) == :dead

  @spec failed?(%JustCurious.Game{}) :: boolean
  def failed?(game), do: get_round(game) == :failed

  @doc """
  A unique string representing the game name and the team it belongs to
  """
  @spec uuid(%JustCurious.Game{}) :: String.t
  def uuid(game), do: "#{game.team}_#{game}"

  @doc """
  Adds a user to the game under the specified `kind` and removes them from any
  other kind they might be on. If the user is not already a participant, they
  are assigned a pseudonym for the game.
  """
  @spec add_participant(%JustCurious.Game{}, String.t, atom) :: :ok
  def add_participant(game, user, kind \\ :player) do
    if user != jc_bot_id(game.team) do # Just Curious can't participate
      game_path = "team:#{game.team}:game:#{game}"

      ~w(player spectator invite join)a |> Enum.each(&(srem("#{game_path}:#{&1}s", user)))

      existing_pseudonym = get_pseudonym(game, user)
      pseudonym          = if existing_pseudonym == :undefined, do: generate_name(game.team, :pseudonym), else: existing_pseudonym

      sadd("#{game_path}:#{kind}s", user)
      hset("#{game_path}:participant:#{user}", "pseudonym", pseudonym)
    end

    :ok
  end

  ## PARTICIPANTS ##
  @spec players(%JustCurious.Game{}) :: [String.t]
  def players(game), do: smembers("team:#{game.team}:game:#{game}:players") |> Enum.sort()

  @spec spectators(%JustCurious.Game{}) :: [String.t]
  def spectators(game), do: smembers("team:#{game.team}:game:#{game}:spectators") |> Enum.sort()

  @spec joins(%JustCurious.Game{}) :: [String.t]
  def joins(game), do: smembers("team:#{game.team}:game:#{game}:joins") |> Enum.sort()

  @spec invites(%JustCurious.Game{}) :: [String.t]
  def invites(game), do: smembers("team:#{game.team}:game:#{game}:invites") |> Enum.sort()

  @spec actives(%JustCurious.Game{}) :: [String.t]
  def actives(game), do: joins(game) ++ players(game)

  @spec participants(%JustCurious.Game{}) :: [String.t]
  def participants(game) do
    sunion([
      "team:#{game.team}:game:#{game}:players",
      "team:#{game.team}:game:#{game}:spectators",
      "team:#{game.team}:game:#{game}:joins",
      "team:#{game.team}:game:#{game}:invites" # TODO Should invites be included here?
    ])
  end

  ## COUNTS ##
  @spec active_player_count(%JustCurious.Game{}) :: integer
  def active_player_count(game), do: actives(game) |> length()

  @spec submission_count(%JustCurious.Game{}) :: integer
  def submission_count(game), do: "team:#{game.team}:game:#{game}:submissions" |> zcard |> String.to_integer

  @spec nomination_count(%JustCurious.Game{}) :: integer
  def nomination_count(game), do: "team:#{game.team}:game:#{game}:submissions" |> zcount(1, "+inf") |> String.to_integer

  @spec answer_count(%JustCurious.Game{}) :: integer
  def answer_count(game) do
    players(game)
      |> Enum.map(fn(user) -> hget("team:#{game.team}:game:#{game}:participant:#{user}", "answer_#{game.chainlink}") end)
      |> Enum.reject(&(&1 == :undefined))
      |> Enum.count
  end

  ## TIES / DEADLOCK ##
  @spec tied?(%JustCurious.Game{}) :: boolean
  def tied?(game) do
    top_two = zrevrange("team:#{game.team}:game:#{game}:submissions", 0, -1)
      |> Enum.take(2)
      |> Enum.map(&(zscore("team:#{game.team}:game:#{game}:submissions", &1)))

    nomination_count(game) > 0 and Enum.at(top_two, 0) == Enum.at(top_two, 1)
  end

  @spec break_tie(%JustCurious.Game{}) :: %JustCurious.Question{}
  def break_tie(game) do
    submitters       = zrevrange("team:#{game.team}:game:#{game}:submissions", 0, -1)
    high_score       = zscore("team:#{game.team}:game:#{game}:submissions", List.first(submitters)) |> String.to_integer()
    submitters
      |> Enum.map(&({zscore("team:#{game.team}:game:#{game}:submissions", &1) |> String.to_integer(), &1}))
      |> Enum.sort()
      |> Enum.reject(fn({score, _submitter}) -> score < high_score end)
      |> Enum.map(fn({_score, submitter}) -> submitter end)
      |> roll_the_dice(game)
  end

  @spec roll_the_dice([String.t], %JustCurious.Game{}) :: :ok
  def roll_the_dice(submitters, game) do
    submitter = if Enum.empty?(submitters) do
      # take randomly from all submitters
      "team:#{game.team}:game:#{game}:submissions" |> zrange(0, -1) |> Enum.random()
    else
      # take randomly from provided submitters
      submitters |> Enum.random()
    end

    zincrby("team:#{game.team}:game:#{game}:submissions", 1, submitter)
    question_id = hget("team:#{game.team}:game:#{game}:participant:#{submitter}", "submission") |> String.to_integer

    JustCurious.Repo.get(JustCurious.Question, question_id)
  end

  ## VARIOUS ##
  @spec winning_question(%JustCurious.Game{}) :: String.t
  def winning_question(game) do
    submitter   = zrevrange("team:#{game.team}:game:#{game}:submissions", 0, -1) |> List.first
    question_id = hget("team:#{game.team}:game:#{game}:participant:#{submitter}", "submission") |> String.to_integer
    JustCurious.Repo.get(JustCurious.Question, question_id)
  end

  @spec generate_name(String.t, atom) :: String.t
  def generate_name(team, kind) do
    next_in_sequence = incr("team:#{team}:generated-names-count:#{kind}")
    JustCurious.NameGenerator.get(kind, next_in_sequence)
  end

  @spec get_pseudonym(%JustCurious.Game{}, String.t) :: String.t
  def get_pseudonym(_game, "just-curious"), do: "just-curious"
  def get_pseudonym(game, user) do
    hget("team:#{game.team}:game:#{game}:participant:#{user}", "pseudonym")
  end

  @spec reattempts(%JustCurious.Game{}, atom) :: integer
  def reattempts(game, round), do: hget("team:#{game.team}:game:#{game}", "#{round}_reattempts") |> String.to_integer
end
