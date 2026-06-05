import { Graph } from '@antv/x6'

function scrollToRightmost(graph) {
  const nodes = graph.getNodes()
  if (!nodes.length) return

  let maxX = -Infinity
  nodes.forEach(n => {
    const bbox = n.getBBox()
    const right = bbox.x + bbox.width
    if (right > maxX) maxX = right
  })

  const container = graph.container
  const viewportWidth = container.clientWidth
  const scale = graph.zoom()
  const rightInView = (viewportWidth - 80) / scale

  if (maxX > rightInView) {
    const dx = rightInView - maxX
    graph.translate(dx, 0)
  }
}


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

  scrollToRightmost(graph)

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
