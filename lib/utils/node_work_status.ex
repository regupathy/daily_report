defmodule NodeWorkStatus do
  defstruct [:job_name, :node, :complete_time, is_complete: false, row_id: 0]

  def new(schedule) do
    joblist =
      for {id, node, job_name} <- schedule,
          into: %{},
          do: {id, %NodeWorkStatus{job_name: job_name, node: node}}

    %{jobs: joblist, start_by: node(), time: Time.utc_now()}
  end

  def update_status(%{id: id, row: row_id}, status) do
    %{status | id => %NodeWorkStatus{status[id] | row_id: row_id}}
  end

  def job_complete(id, status) do
    %{
      status
      | id => %NodeWorkStatus{status[id] | is_complete: true, complete_time: Time.utc_now()}
    }
  end

  def get_jobs(node, status) do
    for {id, %NodeWorkStatus{node: ^node, job_name: job}} <- status.jobs do
      {id, job}
    end
  end

  def get_jobs(ids, node, status) do
    for {id, %NodeWorkStatus{node: ^node, job_name: job}} <- status.jobs, id in ids do
      {id, job}
    end
  end

  def get_incomplete_jobs(nodes, status) do
    for {id, %NodeWorkStatus{node: node, is_complete: false} = task} <- status.jobs,
        node not in nodes do
      id
    end
  end

  def reassign(jobs, node, status) do
    ids =
      for {id, node1} <- jobs do
        work = status.jobs[id]
        status = %{status | jobs: %{status.jobs | id => %{work | node: node1}}}
        id
      end

    {ids, status}
  end
end
