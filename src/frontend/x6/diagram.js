import { Graph } from '@antv/x6'

function initDiagram(containerId, data) {
  const container = document.getElementById(containerId)
  if (!container) throw new Error(`Container not found: ${containerId}`)

  const graph = new Graph({
    container,
    grid: true,
    background: {
      color: '#f5f7fa'
    },
    connecting: {
      router: { name: 'manhattan' },
      connector: { name: 'rounded' },
      connectionPoint: { name: 'anchor' }
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

function resetDiagram(containerId, graph, data) {
  if (graph) {
    graph.dispose()
  }
  return initDiagram(containerId, data)
}

window.initDiagram = initDiagram
window.resetDiagram = resetDiagram
export default initDiagram
