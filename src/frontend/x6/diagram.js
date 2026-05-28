import { Graph } from '@antv/x6'

export default function initDiagram(containerId, data) {
  const container = document.getElementById(containerId)
  if (!container) throw new Error(`Container not found: ${containerId}`)

  const graph = new Graph({
    container,
    grid: true,
    background: {
      color: '#f5f7fa'
    }
  })

  if (data?.nodes) {
    data.nodes.forEach((node) => graph.addNode(node))
  }

  if (data?.edges) {
    data.edges.forEach((edge) => graph.addEdge(edge))
  }

  return graph
}
